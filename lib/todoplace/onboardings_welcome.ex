defmodule Todoplace.Onboardings.Welcome do
  @moduledoc "context module for photographer welcome onboarding"

  alias Todoplace.{
    Repo,
    Onboarding.Welcome
  }

  import Ecto.Query

  def get_all_welcome_states_by_user(user) do
    Repo.all(
      from(
        o in Welcome,
        where: o.user_id == ^user.id,
        order_by: [asc: o.inserted_at]
      )
    )
  end

  def insert_or_update_welcome_by_slug(user, slug, group, generate_completed_at? \\ false) do
    completed_at =
      if generate_completed_at?, do: DateTime.utc_now() |> DateTime.truncate(:second), else: nil

    Repo.insert(
      %Welcome{
        user_id: user.id,
        slug: slug,
        group: group,
        completed_at: completed_at
      },
      on_conflict: :replace_all,
      conflict_target: [:user_id, :slug, :group]
    )
  end

  def group_by_welcome_group(welcome_states) do
    welcome_states
    |> Enum.group_by(& &1.group)
    |> Enum.map(fn {group, states} ->
      {group, states}
    end)
  end

  def get_welcome_state_by_slug_in_group(welcome_groups, slug) do
    welcome_groups
    |> Enum.map(fn {_group, states} ->
      Enum.find(states, fn state -> state.slug == slug end)
    end)
    |> Enum.filter(fn state -> !is_nil(state) end)
    |> Enum.at(0)
  end

  def get_percentage_completed_count(user) do
    total_welcome_states = 15

    completed_welcome_states =
      Repo.aggregate(
        from(o in Welcome,
          where: o.user_id == ^user.id,
          where: not is_nil(o.completed_at)
        ),
        :count
      )

    if total_welcome_states > 0 do
      trunc(completed_welcome_states / total_welcome_states * 100)
    else
      0
    end
  end
end
