export default {
  mounted() {
    this.observer = new IntersectionObserver(entries => {
      if (!entries[0].isIntersecting) {
        this.pushEvent("fix_side_nav", {is_fix: true})
      } else {
        this.pushEvent("fix_side_nav", {is_fix: false})
      }
    }).observe(this.el);
  }
}