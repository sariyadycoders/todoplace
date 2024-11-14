export default {
  mounted() {
    const { hasUser, intercomId } = this.el.dataset;
    const baseSettings = {
      api_base: 'https://api-iam.intercom.io',
      app_id: intercomId,
      custom_launcher_selector: '.open-help',
    };

    if (hasUser === 'true') {
      const {
        name,
        email,
        userId,
        createdAt,
        hasLogo,
        isPublicProfileActive,
        isStripeSetup,
        currencyType,
        acceptedPaymentMethods,
        hasTwoWayCalendarSync,
        numberOfGalleries,
        numberOfContracts,
      } = this.el.dataset;
      const settings = {
        ...baseSettings,
        user_id: userId,
        email,
        name,
        created_at: createdAt,
        has_logo: JSON.parse(hasLogo),
        is_public_profile_active: JSON.parse(isPublicProfileActive),
        is_stripe_setup: JSON.parse(isStripeSetup),
        currency_type: currencyType,
        accepted_payment_methods: JSON.parse(acceptedPaymentMethods),
        has_two_way_calendar_sync: JSON.parse(hasTwoWayCalendarSync),
        number_of_galleries: JSON.parse(numberOfGalleries),
        number_of_contracts: JSON.parse(numberOfContracts),
      };
      window.intercomSettings = settings;
      window?.Intercom('boot', settings);
    } else {
      window.intercomSettings = baseSettings;
      window?.Intercom('boot', baseSettings);
    }
  },
};
