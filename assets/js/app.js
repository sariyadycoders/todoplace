// TODO: Sentry integration -- start
// import * as Sentry from '@sentry/browser';
// import { BrowserTracing } from '@sentry/tracing';

// const env = "development";
//   (window.location.host.includes('render') &&
//     window.location.host.split('.')[0]) ||
//   (process && process.env && process.env.NODE_ENV) ||
//   'production';

// Sentry.init({
//   dsn: 'https://5296991183f042038e40dbe1b1ddb9ef@o1295249.ingest.sentry.io/4504786824921088',
//   integrations: [new BrowserTracing({ tracingOrigins: ['*'] })],
//   environment: env,
  // Set tracesSampleRate to 1.0 to capture 100%
  // of transactions for performance monitoring.
  // We recommend adjusting this value in production
  // tracesSampleRate: 0.1,
// });
// TODO: Sentry integration -- end

import 'phoenix_html';
import { Socket } from 'phoenix';
import topbar from 'topbar';
import { LiveSocket } from 'phoenix_live_view';
import { initializeApp } from 'https://www.gstatic.com/firebasejs/9.23.0/firebase-app.js';
import { getMessaging, getToken, onMessage } from 'https://www.gstatic.com/firebasejs/9.23.0/firebase-messaging.js';

import "../css/app.scss";

// import '@fontsource/be-vietnam/100.css';
// import '@fontsource/be-vietnam/400.css';
// import '@fontsource/be-vietnam/500.css';
// import '@fontsource/be-vietnam/600.css';
// import '@fontsource/be-vietnam/700.css';
import FixSideNav from './hooks/fix-side-nav.js';
import ScrollToTop from './hooks/scroll-to-top.js';
import ScrollToBottom from './hooks/scroll-to-bottom.js';
import Analytics from './hooks/analytics.js';
import AutoHeight from './hooks/auto-height.js';
import Calendar from './hooks/calendar.js';
import CheckIdle from './hooks/check-idle.js';
import ClientGalleryCookie from './hooks/client-gallery-cookie.js';
import Clipboard from './hooks/clipboard.js';
import ClipboardCustom from './hooks/clipboard-custom.js';
import DefaultCostTooltip from './hooks/default-cost-tooltip.js';
import DragDrop from './hooks/drag-drop.js';
import Flash from './hooks/flash.js';
import GalleryMobile from './hooks/gallery-mobile.js';
import GallerySelector from './hooks/gallery-selector.js';
import HandleTrialCode from './hooks/handle-trial-code.js';
import IFrameAutoHeight from './hooks/iframe-auto-height.js';
import ImageUploadInput from './hooks/image-upload-input.js';
import InfiniteScroll from './hooks/infinite-scroll.js';
// import IntroJS from './hooks/intro.js';
import MasonryGrid from './hooks/masonry-grid.js';
import PackageDescription from './hooks/package-description.js';
import PageScroll from './hooks/page-scroll.js';
import PercentMask from './hooks/percent-mask.js';
import Phone from './hooks/phone.js';
import PhotoUpdate from './hooks/photo-update.js';
import PlacesAutocomplete from './hooks/places-autocomplete.js';
import PrefixHttp from './hooks/prefix-http.js';
import Preview from './hooks/preview.js';
import PriceMask from './hooks/price-mask.js';
import Quill, { ClearQuillInput } from './hooks/quill.js';
import ResumeUpload from './hooks/resume_upload.js';
import ScrollIntoView from './hooks/scroll-into-view.js';
import Select from './hooks/select.js';
import ToggleContent from './hooks/toggle-content.js';
import ToggleSiblings from './hooks/toggle-siblings.js';
import DatePicker from './hooks/date-picker.js';
import BeforeUnload from './hooks/before-unload.js';
import Cookies from 'js-cookie';
import FolderUpload from './hooks/folder-upload.js';
import SearchResultSelect from './hooks/search-result-select.js';
import Tooltip from './hooks/tooltip.js';
import StripeElements from './hooks/stripe-elements.js';
import DisableRightClick from './hooks/disable-right-click.js';
import Timer from './hooks/timer.js';
import LivePhone from 'live_phone';
import ViewProposal from './hooks/view_proposal.js';
import CustomFileUploader from './hooks/custom-file-uploader.js';
import Sortable from './hooks/sortable.js';
import OpenCompose from './hooks/open_compose.js';
import CollapseSidebar from './hooks/collapse-sidebar.js';
import Confetti from './hooks/confetti.js';
import TriggerDownload from './hooks/trigger-download.js';
import BookingEventCalendar from './hooks/booking-event-calendar.js';
import IntercomPush from './hooks/intercom-push.js';
import IntercomLoad from './hooks/intercom-load.js';
import Drop from './hooks/drop.js';
import PreventContextMenu from "./hooks/prevent_context_menu.js";
import AddOrganizationMenu from "./hooks/add-organization-menu.js";


const Modal = {
  mounted() {
    this.el.addEventListener('mousedown', (e) => {
      const targetIsOverlay = (e) => e.target.id === 'modal-wrapper';

      if (targetIsOverlay(e)) {
        const mouseup = (e) => {
          if (targetIsOverlay(e)) {
            this.pushEvent('modal', { action: 'close' });
          }
          this.el.removeEventListener('mouseup', mouseup);
        };
        this.el.addEventListener('mouseup', mouseup);
      }
    });

    this.keydownListener = (e) => {
      if (e.key === 'Escape') {
        this.pushEvent('modal', { action: 'close' });
      }
    };

    document.addEventListener('keydown', this.keydownListener);

    this.handleEvent('modal:open', () => {
      document.body.classList.add('overflow-hidden');
    });

    this.handleEvent('modal:close', () => {
      this.el.classList.add('opacity-0');
      document.body.classList.remove('overflow-hidden');
    });
  },

  destroyed() {
    document.removeEventListener('keydown', this.keydownListener);
    document.body.classList.remove('overflow-hidden');
  },
};

const ClearInput = {
  mounted() {
    const { el } = this;
    const {
      dataset: { inputName },
    } = el;

    const input = this.el
      .closest('form')
      .querySelector(`*[name*='${inputName}']`);

    let inputWasFocussed = false;

    input.addEventListener('blur', (e) => {
      inputWasFocussed = e.relatedTarget === el;
    });

    this.el.addEventListener('click', () => {
      input.value = null;
      input.dispatchEvent(new Event('input', { bubbles: true }));
      if (inputWasFocussed) input.focus();
    });
  },
};

const OnboardingCookie = {
  mounted() {
    function getQueryParam(paramName) {
      const urlParams = new URLSearchParams(window.location.search);
      return urlParams.get(paramName);
    }

    const { timeZone } = Intl.DateTimeFormat().resolvedOptions();
    document.cookie = `time_zone=${timeZone}; path=/`;
    document.cookie =`user_agent=${encodeURIComponent(navigator.userAgent)}; path=/;`;

    if (getQueryParam('onboarding_type')) {
      document.cookie = `onboarding_type=${getQueryParam(
        'onboarding_type'
      )}; path=/`;
    }
  },
};


const UserAgent = {
  mounted() {
    document.cookie =`user_agent=${encodeURIComponent(navigator.userAgent)}; path=/;`;
  },
};


const ShowLoader = {
  mounted() {
    this.el.addEventListener("click", () => {
      document.getElementById('loader').classList.remove('hidden');
    });
  }
}

const SetCurrentPath = {
  mounted() {
    let currentPath = window.location.pathname;
    // this.pushEventTo(this.el.dataset.target, 'set_current_path', { path: currentPath });
    this.pushEvent("set_current_path", { path: currentPath });
  },
};

const CardStatus = {
  mounted() {
    this.el.addEventListener('click', () => {
      this.pushEvent('card_status', {
        status: this.el.dataset.status,
        org_card_id: this.el.id,
      });
    });
  },
};

const FinalCostInput = {
  mounted() {
    let dataset = this.el.dataset;
    let inputElm = document.getElementById(dataset.inputId);

    inputElm.addEventListener('input', () => {
      if (inputElm.value.replace('$', '') < parseFloat(dataset.baseCost)) {
        let span = document.getElementById(dataset.spanId);
        span.style.color = 'red';

        setTimeout(function () {
          span.style.color = 'white';
          inputElm.value = `$${parseFloat(dataset.finalCost).toFixed(2)}`;
        }, 3000);
      }
    });
  },
};

const showWelcomeModal = {
  mounted() {
    const show = Cookies.get('redirect_welcome_route');

    if (show == 'true') {
      const dateTime = new Date('1970-12-17T00:00:00');
      Cookies.set('redirect_welcome_route', false, {
        expires: dateTime,
        path: '/',
      });

      this.pushEvent('redirect-welcome-route', {});
    }
  },
};

const handleAdminCookie = () => {
  const show = Cookies.get('show_admin_banner');

  if (show == 'true') {
    document?.querySelector('#admin-banner')?.classList?.remove('hidden');
  }
};

const showAdminBanner = {
  mounted() {
    handleAdminCookie();
  },
  updated() {
    handleAdminCookie();
  },
};

const PreserveToggleState = {
  mounted() {
    this.el.addEventListener('click', (e) => {
      var checked_value = document.getElementById('toggle-button').checked;
      document.getElementById('toggle-button').checked = !checked_value;
      var sequence_value = document.getElementById(
        this.el.dataset.elementId
      ).checked;
      document.getElementById(this.el.dataset.elementId).checked =
        !sequence_value;
    });
  },
};
const ToggleContents = {
  mounted() {
    this.el.addEventListener("click", (e) => {
      e.stopPropagation();
      this.el.querySelector(".toggle-content").classList.toggle("hidden");
    });

    document.addEventListener("click", () => {
      this.el.querySelector(".toggle-content").classList.add("hidden");
    });
  },
};
const Hooks = {
  SetCurrentPath,
  FixSideNav,
  ScrollToTop,
  ScrollToBottom,
  AutoHeight,
  Calendar,
  CheckIdle,
  ClearInput,
  ClearQuillInput,
  ClientGalleryCookie,
  Clipboard,
  ClipboardCustom,
  DatePicker,
  BeforeUnload,
  DefaultCostTooltip,
  DragDrop,
  Drop,
  Flash,
  GalleryMobile,
  GallerySelector,
  HandleTrialCode,
  IFrameAutoHeight,
  ImageUploadInput,
  InfiniteScroll,
  // IntroJS,
  MasonryGrid,
  Modal,
  PackageDescription,
  PageScroll,
  PercentMask,
  Phone,
  PhotoUpdate,
  PlacesAutocomplete,
  PrefixHttp,
  Preview,
  PriceMask,
  Quill,
  ResumeUpload,
  ScrollIntoView,
  Select,
  OnboardingCookie,
  ToggleContent,
  ToggleSiblings,
  Tooltip,
  TriggerDownload,
  CardStatus,
  FinalCostInput,
  showWelcomeModal,
  showAdminBanner,
  FolderUpload,
  StripeElements,
  SearchResultSelect,
  DisableRightClick,
  Timer,
  LivePhone,
  ViewProposal,
  CustomFileUploader,
  Sortable,
  PreserveToggleState,
  OpenCompose,
  CollapseSidebar,
  Confetti,
  BookingEventCalendar,
  IntercomPush,
  IntercomLoad,
  PreventContextMenu,
  AddOrganizationMenu,
  ToggleContents,
  UserAgent,
  ShowLoader
};

window.addEventListener(`phx:download`, (event) => {
  let frame = document.createElement('iframe');
  frame.setAttribute('src', event.detail.uri);
  frame.style.visibility = 'hidden';
  frame.style.display = 'none';
  document.body.appendChild(frame);
});

let Uploaders = {};
Uploaders.GCS = function (entries, onViewError) {
  (function (items) {
    let queue = [];
    const try_next = () =>
      setTimeout(() => {
        const next = queue.shift();
        if (next) {
          go(next);
        }
      }, 10);

    const go = (entry) => {
      let formData = new FormData();
      let { url, fields } = entry.meta;

      Object.entries(fields).forEach(([key, val]) => formData.append(key, val));
      formData.append('file', entry.file);

      let xhr = new XMLHttpRequest();
      onViewError(() => {
        try_next();
        xhr.abort();
      });
      xhr.onload = () => {
        try_next();
        xhr.status === 204 ? entry.progress(100) : entry.error();
      };
      xhr.onerror = () => {
        try_next();
        entry.error();
      };
      xhr.upload.addEventListener('progress', (event) => {
        if (event.lengthComputable) {
          let percent = Math.round((event.loaded / event.total) * 100);
          if (percent < 100) {
            entry.progress(percent);
          }
        }
      });
      xhr.open('POST', url, true);
      xhr.send(formData);
    };

    queue = items.splice(5);

    items.forEach(go);
  })(entries);
};

let csrfToken = document
  .querySelector("meta[name='csrf-token']")
  .getAttribute('content');
let liveSocket = new LiveSocket('/live', Socket, {
  hooks: Hooks,
  params: { _csrf_token: csrfToken, isMobile: window.innerWidth <= 768 },
  uploaders: Uploaders,
});

// Show progress bar on live navigation and form submits
topbar.config({
  barColors: { 0: '#00ADC9' },
  shadowColor: 'rgba(0, 0, 0, .3)',
});
let topBarScheduled = undefined;
window.addEventListener('phx:page-loading-start', () => {
  if (!topBarScheduled) {
    topBarScheduled = setTimeout(() => topbar.show(), 120);
  }
});
window.addEventListener('phx:page-loading-stop', (info) => {
  clearTimeout(topBarScheduled);
  topBarScheduled = undefined;
  topbar.hide();
  Analytics.init(info);
});

window.addEventListener('phx:scroll:lock', () => {
  document.body.classList.add('overflow-hidden');
});

window.addEventListener('phx:scroll:unlock', () => {
  document.body.classList.remove('overflow-hidden');
});

// connect if there are any LiveViews on the page
liveSocket.connect();

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window['liveSocket'] = liveSocket;
const firebaseConfig = window.FIREBASE_CONFIG;

const app = initializeApp(firebaseConfig);
const messaging = getMessaging(app);
self.addEventListener('push', function(event) {
  console.log('Service Worker registration:', self.registration);
  if (self.registration) {
    const options = {
      body: event.data.text(),
      icon: 'icon.png'
    };
    event.waitUntil(
      self.registration.showNotification('Push Notification Title', options)
    );
  } else {
    console.error('Service Worker registration is undefined');
  }
});

// Request notification permission and get token
document.addEventListener('DOMContentLoaded', async function() {
    try {
        const permission = await Notification.requestPermission();
        console.log('Notification permission status:', permission);
        if (permission === 'granted') {
            console.log('Permission granted');
            const token = await getToken(messaging, { vapidKey: 'BDnozoqst5vqvapkI4QWuZOqK1gLD5Ye0MeSrv8h4QuCp-84lMUK9UYMryzD9azdPlfJy0aIPRcWxrN7Dgf1NII' });
            if (token) {
                console.log('FCM Token:', token);
                // Send the token to your backend
            } else {
                console.log('No registration token available.');
            }
        } else {
            console.error('Notification permission denied');
        }
    } catch (err) {
        console.error('Unable to get permission or retrieve token.', err);
    }

    // Handle incoming messages when the app is in the foreground
    onMessage(messaging, (payload) => {
        console.log('Message received in foreground:', payload);

        // Check if the notification payload exists
        if (payload.notification) {
            const notificationTitle = payload.notification.title;
            const notificationOptions = {
                body: payload.notification.body,
                icon: '/firebase-logo.png'
            };

            // Display notification
            if (Notification.permission === 'granted') {
                // Use the Service Worker to show notifications
                navigator.serviceWorker.getRegistration().then(registration => {
                    if (registration) {
                      console.log('Received background message:', payload);

                      const notificationTitle = payload.notification.title;
                      const notificationOptions = {
                          body: payload.notification.body,
                          icon: '/firebase-logo.png'
                      };
                    console.log(new Notification(notificationTitle, notificationOptions));
                    } else {
                        console.error('Service Worker registration not found.');
                    }
                });
            } else {
                console.log('Notification permission not granted');
            }
        }
    });
});

// Register the service worker
if ('serviceWorker' in navigator) {
    navigator.serviceWorker.register('/firebase-messaging-sw.js')
        .then((registration) => {
            console.log('Service Worker registered with scope:', registration.scope);
        })
        .catch((err) => {
            console.error('Service Worker registration failed:', err);
        });
}