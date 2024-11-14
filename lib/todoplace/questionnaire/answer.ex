defmodule Todoplace.Questionnaire.Answer do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset
  alias Todoplace.{BookingProposal, Questionnaire}

  schema "questionnaire_answers" do
    belongs_to(:proposal, BookingProposal, foreign_key: :proposal_id)
    belongs_to(:questionnaire, Questionnaire)
    field(:answers, {:array, {:array, :string}})

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(answer, attrs) do
    answer
    |> cast(attrs, [:answers, :proposal_id, :questionnaire_id])
    |> validate_required([])
  end
end
