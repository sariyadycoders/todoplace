export default {
  openMobileDrawer() {
    document.body.classList.add('overflow-hidden');
  },
  closeMobileDrawer() {
    document.body.classList.remove('overflow-hidden');
  },
  openDesktopDrawer(main) {
    main.classList.remove('large-margin');
    main.classList.add('small-margin');
    main.classList.remove('large-margin-close');
    main.classList.remove('small-margin-close');
  },
  closeDesktopDrawer(main) {
    main.classList.add('large-margin');
    main.classList.remove('small-margin');
    main.classList.remove('large-margin-close');
    main.classList.remove('small-margin-close');
  },
  openDesktopDrawerTwo(main) {
    main.classList.remove('large-margin');
    main.classList.remove('small-margin');
    main.classList.remove('large-margin-close');
    main.classList.add('small-margin-close');
  },
  closeDesktopDrawerTwo(main) {
    main.classList.remove('large-margin');
    main.classList.remove('small-margin');
    main.classList.add('large-margin-close');
    main.classList.remove('small-margin-close');
  },
  
  mounted() {
    const main = document.querySelector('main');

    this.el.addEventListener('mousedown', (e) => {
      const targetIsOverlay = (e) => e.target.id === 'sidebar-wrapper';

      if (targetIsOverlay(e)) {
        const mouseup = (e) => {
          if (targetIsOverlay(e)) {
            this.pushEventTo(this.el.dataset.target, 'open');
          }
          this.el.removeEventListener('mouseup', mouseup);
        };
        this.el.addEventListener('mouseup', mouseup);
      }
    });

    this.handleEvent('sidebar:mobile', ({ is_drawer_open }) => {
      is_drawer_open
        ? this.closeMobileDrawer(main)
        : this.openMobileDrawer(main);
    });

    this.handleEvent(
      'sidebar:update_onboarding_percentage',
      ({ onboarding_percentage }) => {
        const percentageToString = `${onboarding_percentage}%`;
        const parent = document.querySelector('#sidebar-onboarding');
        if (parent) {
          const progressBar = parent.querySelector('progress');
          const percentage = parent.querySelector('.js--percentage');
          progressBar.value = onboarding_percentage;
          progressBar.innerHTML = percentageToString;
          percentage.innerHTML = percentageToString;
        }
      }
    );

    this.handleEvent('sidebar:collapse', ({ is_drawer_open, is_firstlayer }) => {
      if (is_firstlayer && is_drawer_open) {
        this.closeDesktopDrawer(main)
      } else if (!is_firstlayer && is_drawer_open) {
        this.closeDesktopDrawerTwo(main)
      } else if (is_firstlayer && !is_drawer_open) {
        this.openDesktopDrawer(main);
      } else {
        this.openDesktopDrawerTwo(main);
      }
    });
  },
};
