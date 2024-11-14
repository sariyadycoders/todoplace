defmodule Todoplace.EmailPresets.JobResolver do
  @moduledoc "resolves job/lead mustache variables"

  defstruct [:job, :payment_schedule, :helpers]

  def new({%Todoplace.Job{} = job}, helpers),
    do: %__MODULE__{
      job: preload_job(job),
      helpers: helpers
    }

  # TODO: handle me (scheme issue)
  # def new({%Core.Job{} = job, %Core.PaymentSchedule{} = payment_schedule}, helpers),
  #   do: %__MODULE__{
  #     job: preload_job(job),
  #     payment_schedule: payment_schedule,
  #     helpers: helpers
  #   }

  # to be replaced with above
  def new({job, payment_schedule}, helpers),
    do: %__MODULE__{
      job: preload_job(job),
      payment_schedule: payment_schedule,
      helpers: helpers
    }

  defp preload_job(job),
    do:
      Todoplace.Repo.preload(job, [
        :booking_proposals,
        :booking_event,
        :package,
        :shoots,
        client: [organization: :user]
      ])

  defp client(%__MODULE__{job: job}), do: Todoplace.Repo.preload(job, :client).client

  defp organization(%__MODULE__{} = resolver),
    do: resolver |> client() |> Todoplace.Repo.preload(:organization) |> Map.get(:organization)

  defp photographer(%__MODULE__{} = resolver),
    do: resolver |> organization() |> Todoplace.Repo.preload(:user) |> Map.get(:user)

  defp current_proposal(%__MODULE__{job: job}),
    do:
      job
      |> Todoplace.Repo.preload(:booking_proposals)
      |> Map.get(:booking_proposals)
      |> Enum.sort_by(& &1.updated_at, DateTime)
      |> List.last()

  defp next_shoot(%__MODULE__{job: job}) do
    job
    |> Todoplace.Repo.preload(:shoots)
    |> Map.get(:shoots)
    |> Enum.filter(&(DateTime.compare(&1.starts_at, DateTime.utc_now()) == :gt))
    |> Enum.sort_by(& &1.starts_at, DateTime)
    |> case do
      [next_shoot | _rest] -> next_shoot
      _ -> nil
    end
  end

  ## Retrieves the name of a booking event associated with a job or the job's name.
  ## This private function takes a map representing a job and retrieves the name of
  ## the booking event associated with the job. If a booking event is associated with
  ## the job, it returns the booking event's name. If not, it returns the name of the job itself.
  defp booking_event_name(job) do
    booking_event = Map.get(job, :booking_event)
    if booking_event, do: booking_event.name, else: Todoplace.Job.name(job)
  end

  defp booking_event_id(job), do: Map.get(job, :booking_event_id)

  defp strftime(%__MODULE__{helpers: helpers} = resolver, date, format) do
    resolver |> photographer() |> Map.get(:time_zone) |> helpers.strftime(date, format)
  end

  defp package(%__MODULE__{job: job}), do: Todoplace.Repo.preload(job, :package).package

  defp noop(%__MODULE__{}), do: nil

  defp helpers(%__MODULE__{helpers: helpers}), do: helpers

  def vars,
    do: %{
      "brand_sentence" => &noop/1,
      "client_first_name" => &(&1 |> client() |> Map.get(:name) |> String.split() |> hd),
      "client_full_name" => &(&1 |> client() |> Map.get(:name)),
      "delivery_expectations_sentence" => &noop/1,
      "delivery_time" =>
        &with(
          %{turnaround_weeks: weeks} <- package(&1),
          do:
            helpers(&1).ngettext(
              "one week",
              "%{count} weeks",
              weeks
            )
        ),
      # handled in sendgrid template
      "email_signature" => &noop/1,
      "invoice_amount" => &Todoplace.PaymentSchedules.remainder_price(&1.job),
      "invoice_due_date" =>
        &with(
          %DateTime{} = due_on <- Todoplace.PaymentSchedules.remainder_due_on(&1.job),
          do:
            strftime(
              &1,
              due_on,
              "%b %-d, %Y"
            )
        ),
      "invoice_link" =>
        &with(
          %Todoplace.BookingProposal{id: proposal_id} <- current_proposal(&1),
          do: """
            <a target="_blank" href="#{Todoplace.BookingProposal.url(proposal_id)}">
              Invoice Link
            </a>
          """
        ),
      "job_name" => &Todoplace.Job.name(&1.job),
      "booking_event_name" => &booking_event_name(&1.job),
      "mini_session_link" => &noop/1,
      "booking_event_client_link" => fn resolver ->
        """
          <a target="_blank" href="#{helpers(resolver).client_booking_event_url(organization(resolver).slug, booking_event_id(resolver.job))}">
            Client URL
          </a>
        """
      end,
      "payment_amount" =>
        &case &1.payment_schedule do
          %Todoplace.PaymentSchedule{price: price} -> price
          _ -> nil
        end,
      "photographer_cell" =>
        &case photographer(&1) do
          %Todoplace.Accounts.User{onboarding: %{phone: "" <> phone}} -> phone
          _ -> nil
        end,
      "photography_company_s_name" => &organization(&1).name,
      "pricing_guide_link" => fn resolver ->
        """
          <a target="_blank" href="#{helpers(resolver).profile_pricing_job_type_url(organization(resolver).slug, resolver.job.type)}">
            Guide Link
          </a>
        """
      end,
      "remaining_amount" =>
        &case &1.job do
          %Todoplace.Job{package_id: nil} ->
            nil

          job ->
            Todoplace.PaymentSchedules.owed_price(job)
        end,
      "review_link" => &noop/1,
      "session_date" =>
        &with(
          %{starts_at: starts_at} <- next_shoot(&1),
          do: strftime(&1, starts_at, "%B %-d, %Y")
        ),
      "session_location" =>
        &with(
          %Todoplace.Shoot{} = shoot <- next_shoot(&1),
          do: helpers(&1).shoot_location(shoot)
        ),
      "session_time" =>
        &with(
          %{starts_at: starts_at} <- next_shoot(&1),
          do: strftime(&1, starts_at, "%-I:%M %P")
        ),
      "view_proposal_button" =>
        &with(
          %Todoplace.BookingProposal{id: proposal_id} <- current_proposal(&1),
          do: """
          <a style="border:1px solid #1F1C1E;display:inline-block;background:white;color:#1F1C1E;font-family:Montserrat, sans-serif;font-size:18px;font-weight:normal;line-height:120%;margin:0;text-decoration:none;text-transform:none;padding:10px 15px;mso-padding-alt:0px;border-radius:0px;"
             target="_blank"
             href="#{Todoplace.BookingProposal.url(proposal_id)}"> View Proposal <img src="http://cdn.mcauto-images-production.sendgrid.net/69570c0ddcda5224/92587672-4044-4829-8c53-05c260a89d16/8x12.png"></a>
          """
        ),
      "wardrobe_guide_link" => &noop/1,
      "wedding_questionnaire_2_link" => &noop/1,
      "retainer_amount" => &noop/1,
      "faq_page_link" => &noop/1,
      "scheduling_page_link" => &noop/1,
      "photographer_first_name" =>
        &case photographer(&1) do
          %Todoplace.Accounts.User{name: name} -> name |> String.split() |> hd
          _ -> nil
        end
    }
end
