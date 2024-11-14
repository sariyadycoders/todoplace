export default {
  mounted() {
    // Store the handler reference for removal later
    this.contextMenuHandler = (event) => {
      event.preventDefault();
      const orgId = this.el.dataset.orgId;
      const contextMenu = document.getElementById("custom-context-menu");

      // Set the organization ID in the context menu for later use
      contextMenu.dataset.orgId = orgId;
      contextMenu.querySelector('li[phx-click="remove-from-selected-list"]').setAttribute("phx-value-id", orgId);

      this.showCustomMenu(event);
    };
    this.el.addEventListener('contextmenu', this.contextMenuHandler);
  },

  beforeDestroy() {
    // Properly remove the event listener
    this.el.removeEventListener('contextmenu', this.contextMenuHandler);
  },

  showCustomMenu(event) {
    // Get the custom context menu element

    const customMenu = document.getElementById('custom-context-menu');
    
    // Set the position of the custom context menu based on the mouse click
    customMenu.style.left = `${event.pageX}px`;
    customMenu.style.top = `${event.pageY}px`;

    // Make the custom context menu visible
    customMenu.classList.remove('hidden');

    // Add an event listener to hide the menu when clicking outside
    document.addEventListener('click', () => {
      customMenu.classList.add('hidden');
    }, { once: true });
  }
};