defmodule TodoplaceWeb.Layouts do
  @moduledoc """
  This module holds different layouts used by your application.

  See the `layouts` directory for all templates available.
  The "root" layout is a skeleton rendered as part of the
  application router. The "app" layout is set as the default
  layout on both `use TodoplaceWeb, :controller` and
  `use TodoplaceWeb, :live_view`.
  """
  use TodoplaceWeb, :html

  import TodoplaceWeb.LayoutView
  import TodoplaceWeb.Shared.Sidebar, only: [main_header: 1, get_classes_for_main: 1]
  import TodoplaceWeb.Shared.Outerbar, only: [outer_header: 1]
  import TodoplaceWeb.Shared.StickyUpload, only: [sticky_upload: 1, gallery_top_banner: 1]
  import TodoplaceWeb.LiveHelpers, only: [icon: 1, classes: 2]
  import TodoplaceWeb.UserControlsComponent
  import TodoplaceWeb.LayoutView
  import TodoplaceWeb.Shared.Sidebar, only: [main_header: 1, get_classes_for_main: 1]
  import TodoplaceWeb.Shared.StickyUpload, only: [sticky_upload: 1, gallery_top_banner: 1]
  import TodoplaceWeb.LiveHelpers, only: [icon: 1, classes: 2]

  embed_templates "layouts/*"
end
