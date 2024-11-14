defmodule Todoplace.Workers.PrefillSigningUpUser do
  @moduledoc """
  PrefillSigningUpUser module is responsible for performing initial setup for a signing-up user in the Todoplace application.
  It creates necessary database entries, associates clients, jobs, galleries, and performs additional tasks like sending welcome emails.

  ## Usage

  This module is designed to be used as an Oban worker.

  Example:
  ```elixir
    :ok = Todoplace.Workers.PrefillSigningUpUser.perform(user)
  ```
  """

  use Oban.Worker,
    unique: [period: :infinity, states: ~w[available scheduled executing retryable]a]

  alias Todoplace.{
    Repo,
    Clients,
    Job,
    ClientMessage,
    Package,
    BookingProposal,
    Galleries,
    Galleries.Gallery,
    Galleries.GalleryClient,
    Galleries.GalleryProduct,
    Galleries.Photo,
    Galleries.Workers.PhotoStorage,
    Utils,
    Currency,
    Category,
    Questionnaire,
    Shoot,
    PaymentSchedule,
    PackagePaymentSchedule
  }

  alias Ecto.Multi
  import Ecto.Query

  import TodoplaceWeb.GalleryLive.Shared, only: [start_photo_processing: 2]

  def perform(user) do
    {:ok, %{hermione_client: hermione_client, gallery: gallery}} =
      Task.async(fn -> prefill_initial_information(user) end) |> Task.await()

    upload_photos(hermione_client, gallery)
    :ok
  end

  def prefill_initial_information(%{organization_id: organization_id} = user) do
    Multi.new()
    |> client_multi(organization_id)
    |> insert_defaults(organization_id)
    |> Multi.insert(:lead, fn changes ->
      Job.create_job_changeset(%{
        type: "family",
        job_name: "Taylor Fast Family",
        client_id: changes.taylor_client.id
      })
    end)
    |> insert_associations("lead", organization_id, %{
      base_price: %Money{amount: 79_500, currency: :USD},
      buy_all: %Money{amount: 50_000, currency: :USD},
      collected_price: nil,
      description: "LEAD Package",
      download_count: 15,
      currency: "USD",
      download_each_price: %Money{amount: 5000, currency: :USD},
      name: "Family Package",
      organization_id: organization_id,
      shoot_count: 1,
      job_type: "family"
    })
    |> Multi.insert(:client_message, fn changes ->
      message_params = %{
        "body_text" =>
          """
          Welcome #{strip_photographers_first_name(user.name)}

          We are really excited you are here! This is your inbox where you will receive your client emails and also be quickly able to respond to them! It looks like a text message but rest assured it comes through like a regular email with your logo and signature (head here to upload your logo to create that!)

          If you have any questions as you get set up, simply head to the chat button at the bottom of the screen and our support team will take great care of you!

          We’d love to know how we can help you, simply reply to this email and let us know what you are needing help with! We can’t wait to see how your business grows with Todoplace.

          Cheers,
          Jane
          """
          |> body_text_to_html(),
        "subject" => "Welcome to Todoplace!",
        "job_id" => changes.initial_lead.id
      }

      ClientMessage.create_inbound_changeset(message_params)
    end)
    |> Multi.insert(:job, fn changes ->
      Job.create_job_changeset(%{
        type: "family",
        job_name: "Hermione Potter",
        client_id: changes.hermione_client.id
      })
    end)
    |> insert_associations("job", organization_id, %{
      "name" => "Family Package",
      "base_price" => Money.new(49_500, :USD),
      "buy_all" => Money.new(25_000, :USD),
      "currency" => "USD",
      "download_count" => 7,
      "download_each_price" => Money.new(5000, :USD),
      "collected_price" => nil,
      "organization_id" => organization_id,
      "shoot_count" => 1,
      "job_type" => "family"
    })
    |> gallery_multi(user)
    |> Repo.transaction()
  end

  defp client_multi(multi, organization_id) do
    client_params = %{"name" => "Jane Goodrich", "email" => "support@todoplace.com"}
    taylor_client_params = %{"name" => "Taylor Fast", "email" => "taylor.fast@todoplace.com"}

    hermione_client_params = %{
      "name" => "Hermione Potter",
      "email" => "hermione.potter@todoplace.com"
    }

    multi
    |> Multi.insert(:client, Clients.new_client_changeset(client_params, organization_id))
    |> Multi.insert(
      :taylor_client,
      Clients.new_client_changeset(taylor_client_params, organization_id)
    )
    |> Multi.insert(
      :hermione_client,
      Clients.new_client_changeset(hermione_client_params, organization_id)
    )
  end

  defp insert_defaults(multi, organization_id) do
    multi
    |> Multi.insert(:initial_lead, fn changes ->
      Job.create_job_changeset(%{
        type: "global",
        job_name: "Initial Lead Global",
        client_id: changes.client.id
      })
    end)
    |> Multi.insert(:initial_job, fn changes ->
      Job.create_job_changeset(%{
        type: "global",
        job_name: "Initial Job Global",
        client_id: changes.client.id
      })
    end)
    |> insert_package(
      :initial_package,
      %{
        "name" => "Initial Package",
        "base_price" => Money.new(0, :USD),
        "buy_all" => Money.new(0, :USD),
        "currency" => "USD",
        "download_count" => 0,
        "download_each_price" => Money.new(0, :USD),
        "collected_price" => nil,
        "organization_id" => organization_id,
        "shoot_count" => 1,
        "job_type" => "global"
      },
      "job"
    )
    |> Multi.insert(:initial_questionnaire, fn changes ->
      Questionnaire.changeset(
        %Questionnaire{},
        default_questionnaire_params(
          changes.initial_package.id,
          organization_id,
          "initial"
        )
      )
    end)
    |> Multi.update(:update_initial_package, fn changes ->
      Ecto.Changeset.change(
        changes.initial_package,
        questionnaire_template_id: changes.initial_questionnaire.id
      )
    end)
    |> Multi.update(:update_initial_job, fn changes ->
      Job.add_package_changeset(changes.initial_job, %{
        package_id: changes.initial_package.id
      })
    end)
    |> Multi.insert(:initial_proposal, fn changes ->
      BookingProposal.changeset(%{job_id: changes.initial_job.id})
    end)
  end

  defp insert_associations(multi, type, organization_id, attrs) do
    multi
    |> insert_shoot(type)
    |> insert_package(
      if(type == "lead", do: :taylor_package, else: :hermione_package),
      attrs,
      type
    )
    |> insert_questionnaire(organization_id, type)
    |> attach_the_questionnaire(type)
    |> attach_the_package(type)
    |> Multi.insert(if(type == "lead", do: :lead_proposal, else: :job_proposal), fn changes ->
      BookingProposal.changeset(%{
        job_id: if(type == "lead", do: changes.lead.id, else: changes.job.id),
        sent_to_client: if(type == "lead", do: false, else: true)
      })
    end)
    |> then(fn multi ->
      if type == "job",
        do: insert_payment_schedules(multi),
        else: insert_package_payment_schedules(multi)
    end)
  end

  defp insert_shoot(multi, type) do
    multi
    |> Multi.insert((type <> "_shoot") |> String.to_atom(), fn changes ->
      Shoot.changeset(%{
        starts_at: DateTime.utc_now(),
        duration_minutes: 10,
        name: if(type == "job", do: "Harriet's Garden", else: "Family Shoot"),
        location: "studio",
        job_id: if(type == "job", do: changes.job.id, else: changes.lead.id)
      })
    end)
  end

  defp insert_package(multi, multi_name, multi_params, type) do
    multi
    |> then(fn multi ->
      if type == "lead" do
        Multi.insert(multi, multi_name, Ecto.Changeset.change(%Package{}, multi_params))
      else
        Multi.insert(multi, multi_name, Package.import_changeset(multi_params))
      end
    end)
  end

  defp insert_questionnaire(multi, organization_id, type) do
    multi
    |> Multi.insert((type <> "_questionnaire") |> String.to_atom(), fn changes ->
      Questionnaire.changeset(
        %Questionnaire{},
        default_questionnaire_params(
          if(type == "job", do: changes.hermione_package.id, else: changes.taylor_package.id),
          organization_id,
          type
        )
      )
    end)
  end

  defp attach_the_package(multi, type) do
    multi
    |> Multi.update(("attach_package_" <> type) |> String.to_atom(), fn changes ->
      Job.add_package_changeset(if(type == "job", do: changes.job, else: changes.lead), %{
        package_id:
          if(type == "job", do: changes.hermione_package.id, else: changes.taylor_package.id)
      })
    end)
  end

  defp attach_the_questionnaire(multi, type) do
    multi
    |> Multi.update(("update_" <> type <> "_questionnaire") |> String.to_atom(), fn changes ->
      Ecto.Changeset.change(
        if(type == "job", do: changes.hermione_package, else: changes.taylor_package),
        questionnaire_template_id:
          if(type == "job", do: changes.job_questionnaire.id, else: changes.lead_questionnaire.id)
      )
    end)
  end

  defp insert_payment_schedules(multi) do
    multi
    |> Multi.insert_all(:payment_schedules, PaymentSchedule, fn changes ->
      datetime = DateTime.utc_now() |> DateTime.truncate(:second)

      [
        %{
          price: Money.new(24_750, :USD),
          due_at: datetime,
          inserted_at: datetime,
          updated_at: datetime,
          description: "Payment 1",
          job_id: changes.job.id
        },
        %{
          price: Money.new(24_750, :USD),
          due_at: datetime,
          inserted_at: datetime,
          updated_at: datetime,
          description: "Payment 2",
          job_id: changes.job.id
        }
      ]
    end)
  end

  defp insert_package_payment_schedules(multi) do
    multi
    |> Multi.insert_all(:package_payment_schedules, PackagePaymentSchedule, fn _changes ->
      due_at = Date.utc_today()
      timestamps = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_naive()
      schedule_date = DateTime.utc_now() |> DateTime.truncate(:second)

      [
        %{
          description: "Payment 1",
          due_at: due_at,
          inserted_at: timestamps,
          interval: true,
          price: %Money{amount: 39_750, currency: :USD},
          schedule_date: schedule_date,
          updated_at: timestamps
        },
        %{
          description: "Payment 2",
          due_at: due_at,
          inserted_at: timestamps,
          interval: true,
          price: %Money{amount: 39_750, currency: :USD},
          schedule_date: schedule_date,
          updated_at: timestamps
        }
      ]
    end)
  end

  defp default_questionnaire_params(package_id, organization_id, type) do
    questionnaire =
      from(q in Questionnaire,
        where:
          q.job_type == "family" and q.is_todoplace_default and q.is_organization_default == false
      )
      |> Repo.one()
      |> Map.take([:status, :questions, :job_type, :name])

    questions = Enum.map(questionnaire.questions, &Map.from_struct/1)

    %{
      status: questionnaire.status,
      job_type: questionnaire.job_type,
      name:
        cond do
          type == "lead" -> "Family Package"
          type == "job" -> "Harriet's Package"
          true -> "Initial Package"
        end,
      questions: questions,
      package_id: package_id,
      organization_id: organization_id
    }
  end

  @products_currency Utils.products_currency()
  defp gallery_multi(multi, user) do
    multi
    |> Multi.insert(:gallery, fn changes ->
      Gallery.changeset(%Gallery{}, %{
        "name" => "Standard Gallery",
        "job_id" => changes.job.id,
        "status" => "active",
        "password" => "standard gallery"
      })
    end)
    |> Multi.insert_all(:gallery_clients, GalleryClient, fn %{gallery: gallery} ->
      gallery = gallery |> Repo.preload(job: [client: [organization: :user]])
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      client_email = gallery.job.client.email

      client_params = %{
        email: client_email,
        gallery_id: gallery.id,
        inserted_at: now,
        updated_at: now
      }

      if client_email == user.email do
        [client_params]
      else
        [client_params, Map.put(client_params, :email, user.email)]
      end
    end)
    |> Multi.insert_all(
      :gallery_products,
      GalleryProduct,
      fn %{
           gallery:
             %{
               id: gallery_id,
               type: type
             } = gallery
         } ->
        case type do
          :proofing ->
            []

          _ ->
            now = DateTime.utc_now() |> DateTime.truncate(:second)
            currency = Currency.for_gallery(gallery)

            from(category in (Category.active() |> Category.shown()),
              select: %{
                inserted_at: ^now,
                updated_at: ^now,
                gallery_id: ^gallery_id,
                category_id: category.id,
                sell_product_enabled: ^currency in @products_currency
              }
            )
        end
      end
    )
    |> Multi.merge(fn %{gallery: gallery} ->
      gallery
      |> Repo.preload(job: [:client, :package])
      |> Galleries.check_digital_pricing()
    end)
    |> Multi.merge(fn %{gallery: gallery} ->
      gallery
      |> Repo.preload(:package)
      |> Galleries.check_watermark(user)
    end)
  end

  @photo_paths [
    ~s(assets/static/images/initial_info/image-1.jpg),
    ~s(assets/static/images/initial_info/image-5.jpg),
    ~s(assets/static/images/initial_info/image-6.jpg)
  ]
  defp upload_photos(client, gallery) do
    Enum.each(@photo_paths, fn photo ->
      image_name = photo |> String.split("/") |> Enum.at(4) |> String.split(".") |> Enum.at(0)
      file = File.read!(photo)
      path = Photo.original_path(client.name, gallery.id, UUID.uuid4())
      {:ok, entry} = PhotoStorage.insert(path, file)

      {:ok, photo} =
        Galleries.create_photo(%{
          gallery_id: gallery.id,
          album_id: nil,
          name: client.name <> " " <> image_name,
          size: entry.size,
          original_url: path,
          position: (gallery.total_count || 0) + 100
        })

      gallery =
        gallery
        |> Todoplace.Repo.preload([:watermark])

      photo
      |> Todoplace.Repo.preload([:album])
      |> start_photo_processing(gallery)
    end)
  end

  defp strip_photographers_first_name(photographer_name) do
    photographer_name
    |> String.split()
    |> List.first()
  end

  defp body_text_to_html(text),
    do: text |> PhoenixHTMLHelpers.Format.text_to_html() |> Phoenix.HTML.safe_to_string()
end
