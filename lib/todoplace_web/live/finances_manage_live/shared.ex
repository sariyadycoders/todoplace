defmodule TodoplaceWeb.Live.FinancesManage.Shared do
  @moduledoc false
  use Phoenix.Component
  alias Todoplace.{Repo, Orders, PaymentSchedules}
  alias TodoplaceWeb.Live.FinancesManage.OnlinePaymentViewComponent

  def get_galleries_orders(%{
        current_user: user,
        start_date: start_date,
        end_date: end_date,
        search_phrase: search_phrase,
        transaction_source: transaction_source,
        transaction_status: transaction_status,
        transaction_type: transaction_type
      }) do
    if transaction_source != "offline" && transaction_status not in ["pending", "overdue"] do
      Orders.find_all_by_pagination(
        user: user,
        filters: %{
          start_date: start_date,
          end_date: end_date,
          search_phrase: search_phrase
        }
      )
      |> Repo.all()
      |> Enum.map(fn order ->
        {_, _, _, _, total_price} =
          OnlinePaymentViewComponent.total_price_for_gallery_order(order)

        {:ok, price} = Money.parse(total_price)

        Map.merge(
          order,
          %{
            date: order.updated_at,
            price: price,
            client: order.gallery.job.client,
            source: "stripe",
            type: "Gallery-Order",
            status: "Paid"
          }
        )
        |> Map.put_new(:stripe_payment_intent_id, get_stripe_intent_id(order.intent))
      end)
      |> apply_type_filter(transaction_type)
    else
      []
    end
  end

  def get_payment_schedules(%{
        current_user: user,
        start_date: start_date,
        end_date: end_date,
        search_phrase: search_phrase,
        transaction_type: transaction_type,
        transaction_status: transaction_status,
        transaction_source: transaction_source
      }) do
    PaymentSchedules.find_all_by_pagination(
      user: user,
      filters: %{
        start_date: start_date,
        end_date: end_date,
        search_phrase: search_phrase,
        transaction_source: transaction_source,
        transaction_status: transaction_status,
        transaction_type: transaction_type
      }
    )
    |> Repo.all()
    |> determine_types()
    |> apply_transaction_type_filters(transaction_type)
    |> apply_source_filter(transaction_source)
    |> apply_status_filter(transaction_status)
  end

  defp determine_types(payment_schedules) do
    payment_schedules
    |> Enum.group_by(fn ps -> ps.job_id end)
    |> Enum.map(fn {_job_id, schedules} ->
      # Find the last index in the list
      last_index = Enum.count(schedules) - 1

      Enum.with_index(schedules)
      |> Enum.map(fn {transaction, index} ->
        type = if index == last_index, do: "Job-Payment", else: "Job-Retainer"
        source = if(transaction.type == "stripe", do: "Stripe", else: "Offline")
        status = make_status(transaction)

        Map.merge(%{transaction | type: type}, %{source: source, status: status})
      end)
    end)
    |> List.flatten()
  end

  def apply_sort(finances, "updated_at", "desc"),
    do: finances |> Enum.sort_by(& &1.updated_at, {:desc, Date})

  def apply_sort(finances, "updated_at", "asc"),
    do: finances |> Enum.sort_by(& &1.updated_at, {:asc, Date})

  def apply_sort(finances, "price", "desc"), do: finances |> Enum.sort_by(& &1.price, :desc)
  def apply_sort(finances, "price", "asc"), do: finances |> Enum.sort_by(& &1.price, :asc)

  defp apply_transaction_type_filters(_, "gallery-order"), do: []
  defp apply_transaction_type_filters(payment_schedules, "all"), do: payment_schedules

  defp apply_transaction_type_filters(payment_schedules, "job-payment"),
    do: Enum.filter(payment_schedules, &(&1.type == "Job-Payment"))

  defp apply_transaction_type_filters(payment_schedules, "job-retainer"),
    do: Enum.filter(payment_schedules, &(&1.type == "Job-Retainer"))

  defp apply_source_filter(payment_schedules, "all"), do: payment_schedules

  defp apply_source_filter(payment_schedules, "offline"),
    do: Enum.filter(payment_schedules, &(&1.source == "Offline"))

  defp apply_source_filter(payment_schedules, "stripe"),
    do: Enum.filter(payment_schedules, &(&1.source == "Stripe"))

  defp apply_status_filter(payment_schedules, "all"), do: payment_schedules

  defp apply_status_filter(payment_schedules, "overdue"),
    do: Enum.filter(payment_schedules, &(&1.status == "Overdue"))

  defp apply_status_filter(payment_schedules, "paid"),
    do: Enum.filter(payment_schedules, &(&1.status == "Paid"))

  defp apply_status_filter(payment_schedules, "pending"),
    do: Enum.filter(payment_schedules, &(&1.status == "Pending"))

  def split_and_assign_date_range(socket, date_range) do
    case String.split(date_range, " to ") do
      [start_date, end_date] ->
        socket
        |> assign(:start_date, start_date)
        |> assign(:end_date, end_date)

      _ ->
        socket
    end
  end

  def sort_options do
    [
      %{title: "Newset", id: "newest", column: "updated_at", direction: "desc"},
      %{title: "Oldest", id: "oldest", column: "updated_at", direction: "asc"},
      %{title: "Highest", id: "highest", column: "price", direction: "desc"},
      %{title: "Lowest", id: "lowest", column: "price", direction: "asc"}
    ]
  end

  defp make_status(transaction) do
    cond do
      not is_nil(transaction.paid_at) ->
        "Paid"

      DateTime.compare(transaction.due_at, DateTime.utc_now()) == :lt ->
        "Overdue"

      DateTime.compare(transaction.due_at, DateTime.utc_now()) == :gt ->
        "Pending"
    end
  end

  defp apply_type_filter(_gallery_orders, type) when type in ["job-payment", "job-retainer"],
    do: []

  defp apply_type_filter(gallery_orders, type) when type in ["all", "gallery-order"],
    do: gallery_orders

  defp get_stripe_intent_id(nil), do: nil

  defp get_stripe_intent_id(intent), do: intent.stripe_payment_intent_id
end
