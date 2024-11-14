export default {
  mounted() {
    const element = this.el
    console.dir(element)

    element.addEventListener('click', (event) => {
      console.log("INN")
      event.preventDefault();
      copyToClipboard(element.dataset.clipboardText, element);
    });
    
    console.dir("HOOOO")

    console.dir(this.el.dataset.clipboardText)
  },
  destroyed() {
    this.clipboard.destroy();
    this.popper?.destroy();
  },
};

async function copyToClipboard(text, element) {
  try {
    await navigator.clipboard.writeText(text);
    element.innerText = 'Copied !';

      setTimeout(() => {
        element.innerText = 'Copy Field';

      }, 2000);
  } catch (err) {
    console.error('Failed to copy: ', err);
  }
}
