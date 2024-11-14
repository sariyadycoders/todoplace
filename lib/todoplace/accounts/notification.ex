# notification.ex
defmodule Todoplace.Accounts.Notification do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query
  import Todoplace.Repo

  schema "notifications" do
    field :title, :string
    field :body, :string
    belongs_to :user, Todoplace.Accounts.User # Add the user relationship
    belongs_to :organization, Todoplace.Accounts.Organization  # Organization relationship (new)

    timestamps()
  end

  def changeset(notification, attrs) do
    notification
    |> cast(attrs, [:title, :body, :user_id, :organization_id])  # Cast the organization_id as well
    |> validate_required([:title, :body, :user_id, :organization_id])  # Validate that organization_id is required
  end


  def send_notification(user_id, organization_id,  payload) do
    # Get the FCM token from your storage (e.g., database)
    token = "er1H96TkDC1kqVh1Bi75OP:APA91bFK5XxQF8Yw0IbWq0_ua8bkVC1NjLkZDrqwflpEx66MPTZKeRAsuTFPO4My4KonF11nrptmUq_AYA3bK70tgzOsGlJNiyPy_uYpeHcnYwylhWAssVxVYsOTqhGTFom6RkIv8eSD"

    # Assuming your service account file is located in `config/keys/` inside the project directory
    {:ok, access_token} = Todoplace.Auth.GoogleAuth.get_access_token()

    # Send the message via FCM
    TodoplaceWeb.FCM.send_message(access_token, token, payload.title, payload.body)

    # Check if the notification already exists in the database
    existing_notification =
      Todoplace.Accounts.Notification
      |> where([n], n.user_id == ^user_id and n.body == ^payload.body and n.organization_id == ^organization_id)
      |> Todoplace.Repo.one()

    case existing_notification do
      nil ->
        # Insert the notification if it doesn't exist
        changeset = Todoplace.Accounts.Notification.changeset(%Todoplace.Accounts.Notification{}, %{
          "title" => payload.title,
          "body" => payload.body,
          "user_id" => user_id,
          "organization_id" => organization_id
        })

        case Todoplace.Repo.insert(changeset) do
          {:ok, _notification} ->
            # Query the total count of notifications for this user
          notification_count =
            Todoplace.Accounts.Notification
            |> where([n], n.user_id == ^user_id and n.organization_id == ^organization_id)
            |> Todoplace.Repo.aggregate(:count, :id)

            # Broadcast the notification count
            # Phoenix.PubSub.broadcast(Todoplace.PubSub, "organization:#{user_id}", {:update_organization_list, notification_count})
            # IO.inspect "Notification inserted and broadcasted."

          {:error, changeset} ->
            # Handle error
            IO.inspect changeset.errors
        end

      _ ->
        IO.inspect "Notification already exists."
    end
  end
end
