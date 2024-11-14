import JSConfetti from 'js-confetti';

export default {
  mounted() {
    this.handleEvent('confetti', ({ should_fire }) => {
      if (should_fire) {
        const jsConfetti = new JSConfetti();
        jsConfetti.addConfetti({
          emojis: ['📸', '⚡️', '🎉', '✨', '🔥', '📷'],
        });
      }
    });
  },
};
