export default {
  mounted() {
    this.handleEvent('intercom', ({ event }) => {
      console.log('Intercom event', event);
      if (window?.Intercom) {
        window?.Intercom('trackEvent', event);
      }
    });
  },
};
