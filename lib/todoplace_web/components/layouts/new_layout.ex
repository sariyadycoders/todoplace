defmodule TodoplaceWeb.HomeLive.NewLayout do
  use TodoplaceWeb, live_view: [layout: false]

  def render(assigns) do
    ~H"""
    <div style="height: 100%;" class="h-full">
      <div class="h-12 bg-gray-800 flex justify-between fixed left-0 right-0 top-0">
        <div class="flex gap-3 w-1/4 items-center text-white">
          <.icon name="envelope" class="w-5 h-5 text-white ml-4" />
          <div>
            logo
          </div>
          <div class="bg-gray-700 rounded-md px-1">
            FREE EDITION4
          </div>
        </div>
        <div class="flex gap-3 w-1/4 items-center text-white">
          <div class="w-5/6">
            <.form :let={f} for={} as={:form} class="w-full">
              <.input field={f[:search]} type="mattermost-search" placeholder="Search" />
            </.form>
          </div>
          <.icon name="envelope" class="w-5 h-5 text-white" />
        </div>
        <div class="flex gap-3 w-1/4 items-center justify-end text-white">
          <.icon name="envelope" class="w-5 h-5 text-white" />
          <.icon name="envelope" class="w-5 h-5 text-white" />
          <.icon name="envelope" class="w-5 h-5 text-white" />
          <div class="w-9 h-9 rounded-full bg-red-200 mr-4 relative">
            <div class="w-3 h-3 bg-green-400 rounded-full absolute bottom-0 right-0"></div>
          </div>
        </div>
      </div>
      <div class="w-16 bg-gray-800 flex flex-col gap-5 items-center fixed top-12 bottom-0 left-0 pt-2">
        <div class="bg-white rounded-lg h-8 w-9 flex items-center justify-center text-lg ">
          <span>B</span>
        </div>
        <div class="bg-white rounded-lg h-8 w-9 flex items-center justify-center text-lg ">
          <span>B</span>
        </div>
        <div class="bg-white rounded-lg h-8 w-9 flex items-center justify-center text-lg ">
          <span>B</span>
        </div>
        <div class="bg-white rounded-lg h-8 w-9 flex items-center justify-center text-lg ">
          <span>B</span>
        </div>
        <div class="bg-white rounded-lg h-8 w-9 flex items-center justify-center text-lg ">
          <span>B</span>
        </div>
        <div class="bg-white rounded-lg h-8 w-9 flex items-center justify-center text-lg ">
          <span>B</span>
        </div>
      </div>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    {:ok, socket}
  end
end
