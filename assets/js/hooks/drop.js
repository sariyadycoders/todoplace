import GrapesJS from 'grapesjs';
import grapesjsTailwind from 'grapesjs-tailwind';

export default {
    mounted() {
        const editor = GrapesJS.init({
            container: '#gjs',
            plugins: [grapesjsTailwind],
            pluginsOpts: {
              grapesjsTailwind: { /* options */ }
            }
          });

          editor.BlockManager.add('tailwind-button', {
            label: "button",
            content: `
            <div class="flex-col hidden bg-white border rounded-lg shadow-lg popover-content">
            <button title="Go to Stripe" type="button" phx-click="open-stripe"  class="flex items-center px-3 py-2 rounded-lg hover:bg-blue-planning-100 hover:font-bold">
            <.icon name="money-bags" class="inline-block w-4 h-4 mr-2 fill-current text-blue-planning-300" />
              Go to Stripe
            </button>
            <%= if @proposal do %>
            <button title="Mark as paid" type="button" phx-click="open-mark-as-paid" phx-value-user={@current_user.email} class="flex items-center px-3 py-2 rounded-lg hover:bg-blue-planning-100 hover:font-bold">
              <.icon name="checkcircle" class="inline-block w-4 h-4 mr-2 fill-current text-blue-planning-300" />
              Mark as paid
            </button>
            <% end %>
          </div>
            `,
            category: "buttons"
          });
      
          this.handleEvent("update_editor_content", ({ content }) => {
            editor.setComponents(content);
          });
      
          editor.on('component:add', () => {
            const content = editor.getComponents();
            this.pushEvent("save_editor_content", { content });
          });
    },
};
