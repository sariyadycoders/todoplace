defmodule TodoplaceWeb.BookingProposalLive.ContractComponent do
  @moduledoc false

  use TodoplaceWeb, :live_component
  alias Todoplace.{Repo, BookingProposal, Contracts}
  import TodoplaceWeb.LiveModal, only: [close_x: 1, footer: 1]
  import TodoplaceWeb.BookingProposalLive.Shared, only: [visual_banner: 1, items: 1]

  @impl true
  def update(assigns, socket) do
    socket
    |> assign(assigns)
    |> assign_new(:job, fn -> nil end)
    |> assign_new(:shoots, fn -> nil end)
    |> assign_new(:client, fn -> nil end)
    |> assign_new(:proposal, fn -> nil end)
    |> assign_new(:booking_event, fn -> nil end)
    |> assign_changeset()
    |> ok()
  end

  @impl true
  def handle_event("validate", %{"booking_proposal" => params}, socket) do
    socket |> assign_changeset(:validate, params) |> noreply()
  end

  @impl true
  def handle_event("submit", %{"booking_proposal" => params}, socket) do
    case socket |> build_changeset(params) |> Repo.update() do
      {:ok, proposal} ->
        send(self(), {:update, %{proposal: proposal, next_page: "questionnaire"}})

        socket
        |> noreply()

      {:error, _} ->
        socket
        |> put_flash(:error, "Failed to sign contract. Please try again.")
        |> noreply()
    end
  end

  defp build_changeset(%{assigns: %{proposal: nil}}, params) do
    BookingProposal.sign_changeset(%BookingProposal{}, params)
  end

  defp build_changeset(%{assigns: %{proposal: proposal}}, params) do
    proposal
    |> BookingProposal.sign_changeset(params)
  end

  defp assign_changeset(socket, action \\ nil, params \\ %{}) do
    changeset = build_changeset(socket, params) |> Map.put(:action, action)
    assign(socket, changeset: changeset)
  end

  def open_modal_from_proposal(socket, proposal, read_only \\ true) do
    %{
      job:
        %{
          client: client,
          shoots: shoots,
          package:
            %{contract: contract, organization: %{user: photographer} = organization} = package
        } = job
    } =
      proposal |> Repo.preload(job: [:client, :shoots, package: [:contract, organization: :user]])

    socket
    |> open_modal(__MODULE__, %{
      read_only: read_only || proposal.signed_at != nil,
      client: client,
      job: job,
      contract_content:
        Contracts.contract_content(
          contract,
          package,
          TodoplaceWeb.Helpers
        ),
      proposal: proposal,
      package: package,
      shoots: shoots,
      photographer: photographer,
      organization: organization
    })
  end

  def open_modal_from_booking_events(
        %{
          assigns: %{
            current_user: %{organization: organization} = photographer,
            package: %{contract: contract} = package,
            booking_event: booking_event
          }
        } = socket
      ) do
    if is_nil(contract) do
      socket |> put_flash(:error, "Please select a contract first.")
    else
      socket
      |> open_modal(__MODULE__, %{
        read_only: true,
        contract_content:
          Contracts.contract_content(
            contract,
            package,
            TodoplaceWeb.Helpers
          ),
        package: package,
        booking_event: booking_event,
        photographer: photographer,
        organization: organization
      })
    end
  end
end
