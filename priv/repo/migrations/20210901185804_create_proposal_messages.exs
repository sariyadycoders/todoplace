defmodule Todoplace.Repo.Migrations.CreateProposalMessages do
  use Ecto.Migration

  def change do
    create table(:proposal_messages) do
      add(:proposal_id, references(:booking_proposals, on_delete: :nothing), null: false)
      add(:cc_email, :text)
      add(:subject, :text, null: false)
      add(:body_text, :text, null: false)
      add(:body_html, :text)
      add(:scheduled, :boolean, null: false, default: false)

      timestamps()
    end

    create(index(:proposal_messages, [:proposal_id]))
  end
end
