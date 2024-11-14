export default {
  mounted() {
    const menuButton = document.getElementById("nav-organization-menu");

    const menu = document.getElementById("org-context-add-menu");

    menuButton.addEventListener("click", (event) => {
      // Get the mouse click position
      menu.style.left = `${event.pageX}px`;
      menu.style.top = `${event.pageY}px`;

      // Toggle the visibility of the menu
      if (menu.classList.contains("hidden")) {
        // Show the menu
        menu.classList.remove("hidden");

        // Add an event listener to hide the menu after an item is clicked
        menu.addEventListener("click", () => {
          menu.classList.add("hidden");
        }, { once: true }); // Use { once: true } to ensure the listener is removed after it's triggered
      } else {
        // Hide the menu if it was already visible
        menu.classList.add("hidden");
      }
    });
  }
}
