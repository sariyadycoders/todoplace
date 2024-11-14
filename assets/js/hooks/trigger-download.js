export default {
  mounted() {
    this.handleEvent("trigger_download", ({url}) => {
      if (url) {
        window.location.href = url; // Triggers the download
      }
    });
  },
};

