import interactionPlugin from '@fullcalendar/interaction';

const isMobile = () => window.innerWidth <= 768;

const getView = () => {
  return isMobile() ? 'listWeek' : 'dayGridMonth';
};

let calendar = null;
let component = null;

const initializeCalender = (el, component) => {
  const { timeZone, feedPath, currentDate } = el.dataset;
  import("@fullcalendar/core").then(async (Calendar) => {
    const { default: dayGridPlugin } = await import("@fullcalendar/daygrid");
    const { default: timeGridPlugin } = await import("@fullcalendar/timegrid");
    const { default: listPlugin } = await import("@fullcalendar/list");

    calendar = new Calendar(el, {
      themeSystem: 'standard',
      height: 600,
      plugins: [dayGridPlugin, listPlugin, interactionPlugin],
      timeZone,
      initialView: getView(),
      initialDate: currentDate,
      headerToolbar: {
        right: 'today prev next',
        start: 'title',
      },
      eventSources: [{ url: feedPath }],
      selectable: true,
      windowResize: function (view) {
        const newView = getView();
        if (view !== newView) {
          calendar.changeView(getView());
        }
      },
    });

    calendar.on('eventClick', function (info) {
      const dateStr = info.event.start.toISOString().substring(0, 10);
      component.pushEvent('calendar-date-changed', { date: dateStr });
    });

    calendar.on('dateClick', function (info) {
      component.pushEvent('calendar-date-changed', { date: info.dateStr });
      calendar.gotoDate(info.dateStr); // Ensure the calendar view is updated to the clicked date
      calendar.changeView(getView()); // Ensure the month name updates
    });

    calendar.render();
  });
};

export default {
  mounted() {
    component = this;
    const { el } = this;
    const { currentDate, feedPath } = el.dataset;
    initializeCalender(el, component, currentDate, feedPath);
  },
  updated() {
  },
};
