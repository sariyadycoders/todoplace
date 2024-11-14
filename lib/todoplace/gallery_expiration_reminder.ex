defmodule Todoplace.GalleryExpirationReminder do
  @moduledoc false

  alias Todoplace.{
    Galleries,
    Job,
    Notifiers.ClientNotifier,
    ClientMessage,
    Repo
  }

  import Ecto.Query, only: [from: 2]

  def deliver_all(now \\ DateTime.utc_now()) do
    now
    |> DateTime.add(7 * day())
    |> DateTime.truncate(:second)
    |> Galleries.list_soon_to_be_expired_galleries()
    |> Enum.each(&maybe_send_message(&1))
  end

  defp maybe_send_message(%Todoplace.Galleries.Gallery{
         job_id: job_id,
         password: password,
         expired_at: expired_at,
         client_link_hash: client_link_hash
       }) do
    has_gallery_expiration_messages =
      from(r in ClientMessage,
        where: r.subject == "Gallery Expiration Reminder" and r.job_id == ^job_id
      )
      |> Repo.all()

    copy = """
    Hello <%= client_name %>,

    Your gallery is about to expire! Please log into your gallery and make your selections before the gallery expires on <%= expired_at %>

    A reminder your photos are password-protected, so you will need to use this password to view: <%= password %>

    You can log into your private gallery to see all of your images: #{TodoplaceWeb.Endpoint.url()}/gallery/#{client_link_hash}.

    It’s been a delight working with you and I can’t wait to hear what you think!
    """

    if Enum.empty?(has_gallery_expiration_messages) do
      job =
        from(job in Job,
          where: job.id == ^job_id and is_nil(job.archived_at) and is_nil(job.completed_at),
          preload: [client: :organization]
        )
        |> Repo.one()

      if job do
        %{
          client: %{
            id: client_id,
            name: client_name,
            email: client_email,
            organization: %{
              name: organization_name
            }
          }
        } = job

        body =
          EEx.eval_string(copy,
            organization_name: organization_name,
            client_name: client_name,
            password: password,
            expired_at: Calendar.strftime(expired_at, "%m/%d/%y"),
            client_link_hash: client_link_hash
          )

        %{subject: "Gallery Expiration Reminder", body_text: body, body_html: body_html(body)}
        |> ClientMessage.create_outbound_changeset()
        |> Ecto.Changeset.put_change(:job_id, job_id)
        |> Ecto.Changeset.put_change(:client_message_recipients, [
          %{client_id: client_id, recipient_type: :to}
        ])
        |> Ecto.Changeset.put_change(:scheduled, true)
        |> Repo.insert!()
        |> ClientNotifier.deliver_email(%{"to" => client_email})
      end
    end
  end

  defp day(), do: 24 * 60 * 60

  defp body_html(body),
    do: body |> PhoenixHTMLHelpers.Format.text_to_html() |> Phoenix.HTML.safe_to_string()
end
