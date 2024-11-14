defmodule Todoplace.WHCC.Adapter do
  @moduledoc false
  @callback products() :: [Todoplace.WHCC.Product.t()]
  @callback product_details(Todoplace.WHCC.Product.t()) :: Todoplace.WHCC.Product.t()
  @callback designs() :: [Todoplace.WHCC.Design.t()]
  @callback design_details(Todoplace.WHCC.Design.t()) :: Todoplace.WHCC.Design.t()
  @callback editor(map()) :: Todoplace.WHCC.CreatedEditor.t()
  @callback get_existing_editor(String.t(), String.t()) :: Todoplace.WHCC.CreatedEditor.t()
  @callback editor_clone(String.t(), String.t()) :: String.t()
  @callback editor_details(String.t(), String.t()) :: Todoplace.WHCC.Editor.Details.t()
  @callback editors_export(String.t(), [Todoplace.WHCC.Editor.Export.Editor.t()],
              address: Todoplace.Cart.DeliveryInfo.t(),
              entry_id: String.t(),
              reference: String.t()
            ) :: Todoplace.WHCC.Editor.Export.t()
  @callback create_order(String.t(), %Todoplace.WHCC.Editor.Export{}) ::
              {:ok, Todoplace.WHCC.Order.Created.t()} | {:error, any()}
  @callback confirm_order(String.t(), String.t()) :: {:ok, atom()} | {:error, any()}
  @callback webhook_register(String.t()) :: any()
  @callback webhook_verify(String.t()) :: any()
  @callback webhook_validate(any(), String.t()) :: any()

  def products(), do: impl().products()
  def product_details(product), do: impl().product_details(product)

  def designs(), do: impl().designs()
  def design_details(design), do: impl().design_details(design)

  def editor(data), do: impl().editor(data)
  def get_existing_editor(account_id, id), do: impl().get_existing_editor(account_id, id)
  def editor_details(account_id, id), do: impl().editor_details(account_id, id)

  def editors_export(account_id, editors, opts \\ []),
    do: impl().editors_export(account_id, editors, opts)

  def editor_clone(account_id, id), do: impl().editor_clone(account_id, id)

  def create_order(account_id, export),
    do: impl().create_order(account_id, export)

  def confirm_order(account_id, confirmation),
    do: impl().confirm_order(account_id, confirmation)

  def webhook_register(url), do: impl().webhook_register(url)
  def webhook_verify(hash), do: impl().webhook_verify(hash)
  def webhook_validate(data, signature), do: impl().webhook_validate(data, signature)

  defp impl, do: Application.get_env(:todoplace, :whcc) |> Keyword.get(:adapter)
end
