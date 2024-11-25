# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Todoplace.Repo.insert!(%Todoplace.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

defmodule Seeds do
  alias Todoplace.Payments
  alias Todoplace.SubscriptionPlan
  alias Todoplace.Repo

  def sync_subscription_plans do
    {:ok, %{data: prices}} = Payments.list_prices(%{active: true})

    for price <- Enum.filter(prices, &(&1.type == "recurring")) do
      %{
        stripe_price_id: price.id,
        price: price.unit_amount,
        recurring_interval: price.recurring.interval,
        # setting active to false to avoid conflicting prices on sync
        active: false
      }
      |> SubscriptionPlan.changeset()
      |> Repo.insert!(
        conflict_target: [:stripe_price_id],
        on_conflict: {:replace, [:price, :recurring_interval, :updated_at, :active]}
      )
    end
  end

  def run do
    if Mix.env() == :dev do
      sync_subscription_plans()
      Repo.update(SubscriptionPlan.changeset(Repo.get(SubscriptionPlan, 6), %{active: true}))
      Repo.update(SubscriptionPlan.changeset(Repo.get(SubscriptionPlan, 7), %{active: true}))

      Todoplace.Accounts.register_user(%{
        name: "test",
        email: "test@mail.com",
        password: "test@mail.com"
      })
    end
  end
end

Seeds.run()
