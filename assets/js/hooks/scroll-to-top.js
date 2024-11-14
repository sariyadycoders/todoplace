export default {
  mounted() {
    this.el.addEventListener("click", e => {
      window.scrollTo(0, 0);
    })
  }
}