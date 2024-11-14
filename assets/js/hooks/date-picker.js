import flatpickr from 'flatpickr';
import { formatInTimeZone } from 'date-fns-tz';

function buildConfig(dataset) {
  const {
    timeOnly,
    timePicker,
    minDate,
    maxDate,
    customDisplayFormat,
    customDateFormat,
    timeZone,
    mode,
    defaultDate,
    inline
  } = dataset;

  return {
    ...(mode !== undefined ? { mode, defaultDate } : {}),
    wrap: true,
    inline: inline ? true : false,
    enableTime: !!timePicker,
    minDate: minDate ? minDate : null,
    maxDate: maxDate ? maxDate : null,
    noCalendar: !!timeOnly,
    altInput: true,
    altFormat: timePicker
      ? customDisplayFormat || 'm/d/Y h:i K'
      : customDisplayFormat || 'm/d/Y',
    dateFormat: customDateFormat || 'Y-m-d',
    parseDate: (dateStr, format) => {
      if (timeZone) {
        const formatTimezone = formatInTimeZone(
          dateStr,
          timeZone,
          "yyyy-MM-dd'T'HH:mm"
        );

        dateStr = new Date(formatTimezone);
      }
      return flatpickr.parseDate(dateStr, format);
    },
  };
}

export default {
  mounted() {
    const { el } = this;
    this.pickr = flatpickr(el, buildConfig(el.dataset));
  },
  destroyed() {
    this.pickr.destroy();
  },
  updated() {
    const { el } = this;
    const { customDisplayFormat } = el.dataset;

    const wasFormat = this.pickr.config.altFormat;

    if (customDisplayFormat !== wasFormat) {
      this.pickr.destroy();
      this.pickr = flatpickr(el, buildConfig(el.dataset));
    }
  },
};
