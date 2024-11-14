defmodule TodoplaceWeb.GalleryLive.LoaderIcon do
  @moduledoc false
  use TodoplaceWeb, :live_component

  @impl true
  def update(assigns, socket) do
    socket
    |> assign(assigns)
    |> ok
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex sk-circle">
      <div class="sk-circle1 sk-child"></div>
      <div class="sk-circle2 sk-child"></div>
      <div class="sk-circle3 sk-child"></div>
      <div class="sk-circle4 sk-child"></div>
      <div class="sk-circle5 sk-child"></div>
      <div class="sk-circle6 sk-child"></div>
      <div class="sk-circle7 sk-child"></div>
      <div class="sk-circle8 sk-child"></div>
      <div class="sk-circle9 sk-child"></div>
      <div class="sk-circle10 sk-child"></div>
      <div class="sk-circle11 sk-child"></div>
      <div class="sk-circle12 sk-child"></div>
    </div>
    """
  end

  def loader_icon(assigns) do
    ~H"""
    <.live_component id={@id} module={__MODULE__}><%= render_slot(@inner_block) %></.live_component>
    """
  end
end
