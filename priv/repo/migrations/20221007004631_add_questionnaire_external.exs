defmodule Todoplace.Repo.Migrations.AddQuestionnaireExternal do
  use Ecto.Migration

  def change do
    alter table(:questionnaires) do
      add(:organization_id, references(:organizations, on_delete: :nothing))
      add(:package_id, references(:packages, on_delete: :nothing))
      add(:is_organization_default, :boolean, default: false)
      add(:is_todoplace_default, :boolean, default: false)
      add(:name, :string)
    end

    alter table(:packages) do
      add(:questionnaire_template_id, references(:questionnaires, on_delete: :nilify_all))
    end

    execute("""
      update questionnaires set is_todoplace_default = true where organization_id is null and name is null;
    """)
  end

  def down do
    alter table(:questionnaires) do
      remove(:organization_id)
      remove(:package_id)
      remove(:is_organization_default)
      remove(:is_todoplace_default)
      remove(:name)
    end

    alter table(:packages) do
      remove(:questionnaire_template_id)
    end
  end
end
