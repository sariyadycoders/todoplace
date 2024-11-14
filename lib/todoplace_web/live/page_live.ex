defmodule TodoplaceWeb.PageLive do
  @moduledoc false
  use TodoplaceWeb, live_view: [layout: :onboarding]

  @impl true
  def mount(_params, session, socket) do
    socket
    |> assign_defaults(session)
    |> assign(%{
      meta_attrs: %{
        description:
          "Manage, market, and monetize your photography business.  Let Todoplace help elevate your professional photography business with our all-in-one, intuitive software."
      }
    })
    |> ok()
  end
end
