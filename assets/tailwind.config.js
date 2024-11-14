// See the Tailwind configuration guide for advanced usage
// https://tailwindcss.com/docs/configuration

import plugin from 'tailwindcss/plugin';
import fs from 'fs';
import path from 'path';
import defaultTheme from 'tailwindcss/defaultTheme';
import svgToDataUri from 'mini-svg-data-uri';

const safelist = ['border', 'text', 'bg', 'hover:border']
  .map((pre) =>
    [
      'red-sales-300',
      'purple-marketing-300',
      'orange-inbox-300',
      'blue-planning-300',
    ].map((c) => [pre, c].join('-'))
  )
  .flat();

const combineValues = (values, prefix, cssProperty) =>
  Object.keys(values).reduce(
    (acc, key) => ({
      ...acc,
      ...(typeof values[key] === 'string'
        ? {
            [`${prefix}-${key}`]: {
              [cssProperty]: values[key],
            },
          }
        : combineValues(values[key], `${prefix}-${key}`, cssProperty)),
    }),
    {}
  );

module.exports = {
  content: [
    './js/**/*.js',
    '../lib/*.ex',
    '../lib/**/*.*ex',
    '../lib/**/*.*heex',
  ],
  theme: {
    extend: {
      colors: {
        brand: '#FD4F00',
        current: 'currentColor',
        gray: { 700: '#374151' },
        base: {
          350: '#231F20',
          300: '#1F1C1E',
          250: '#898989',
          225: '#C9C9C9',
          200: '#EFEFEF',
          150: '#E3E3E3',
          100: '#FFFFFF',
        },
        toggle: { 100: '#50ACC4' },
        'blue-gallery': {
          400: '#4DAAC6',
          300: '#6696F8',
          200: '#92B6F9',
          100: '#E1EBFD',
        },
        'red-sales': { 300: '#E1662F', 200: '#EF8F83', 100: '#FDF2F2' },
        'blue-planning': { 300: '#4DAAC6', 200: '#86C3CC', 100: '#F2FDFB' },
        'yellow-files': { 300: '#F7CB45', 200: '#FAE46B', 100: '#FEF9E2' },
        'purple-marketing': { 300: '#5464B2', 200: '#687DE1', 100: '#C9D2FF' },
        'orange-inbox': {
          400: '#FCF0EA',
          300: '#F19D4A',
          200: '#F5BD7F',
          100: '#FDF4E9',
        },
        'green-finances': { 300: '#429467', 200: '#81CF67', 100: '#CFE7CD' },
        'red-error': { 300: '#F60000' },
      },
      fontFamily: {
        sans: ['Be Vietnam', ...defaultTheme.fontFamily.sans],
        client: ['"Avenir LT Std"'],
      },
      spacing: {
        '5vw': '5vw',
      },
      fontSize: {
        '13px': '13px',
        '16px': '16px',
        '15px': '15px',
      },
      boxShadow: {
        md: '0px 4px 4px 0px rgba(0, 0, 0, 0.25)',
        lg: '0px 4px 14px 0px rgba(0, 0, 0, 0.15)',
        xl: '0px 14px 14px 0px rgba(0, 0, 0, 0.20)',
        top: '0px -14px 34px rgba(0, 0, 0, 0.15)',
      },
      zIndex: { '-10': '-10' },
      strokeWidth: { 3: '3', 4: '4' },
      gridTemplateColumns: {
        cart: '110px minmax(80px, 1fr) auto',
        cartWide: '16rem 1fr auto',
      },
      gridTemplateRows: {
        preview: '50px auto',
      },
    },
  },
  plugins: [
    require('@tailwindcss/forms'),
    // Allows prefixing tailwind classes with LiveView classes to add rules
    // only when LiveView classes are applied, for example:
    //
    //     <div class="phx-click-loading:animate-ping">
    //
    plugin(({ addVariant }) =>
      addVariant('phx-no-feedback', ['.phx-no-feedback&', '.phx-no-feedback &'])
    ),
    plugin(({ addVariant }) =>
      addVariant('phx-click-loading', [
        '.phx-click-loading&',
        '.phx-click-loading &',
      ])
    ),
    plugin(({ addVariant }) =>
      addVariant('phx-submit-loading', [
        '.phx-submit-loading&',
        '.phx-submit-loading &',
      ])
    ),
    plugin(({ addVariant }) =>
      addVariant('phx-change-loading', [
        '.phx-change-loading&',
        '.phx-change-loading &',
      ])
    ),

    // Embeds Heroicons (https://heroicons.com) into your app.css bundle
    // See your `CoreComponents.icon/1` for more information.
    //
    plugin(function ({ matchComponents, theme }) {
      let iconsDir = path.join(__dirname, '../deps/heroicons/optimized');
      let values = {};
      let icons = [
        ['', '/24/outline'],
        ['-solid', '/24/solid'],
        ['-mini', '/20/solid'],
        ['-micro', '/16/solid'],
      ];
      icons.forEach(([suffix, dir]) => {
        fs.readdirSync(path.join(iconsDir, dir)).forEach((file) => {
          let name = path.basename(file, '.svg') + suffix;
          values[name] = { name, fullPath: path.join(iconsDir, dir, file) };
        });
      });
      matchComponents(
        {
          hero: ({ name, fullPath }) => {
            let content = fs
              .readFileSync(fullPath)
              .toString()
              .replace(/\r?\n|\r/g, '');
            let size = theme('spacing.6');
            if (name.endsWith('-mini')) {
              size = theme('spacing.5');
            } else if (name.endsWith('-micro')) {
              size = theme('spacing.4');
            }
            return {
              [`--hero-${name}`]: `url('data:image/svg+xml;utf8,${content}')`,
              '-webkit-mask': `var(--hero-${name})`,
              mask: `var(--hero-${name})`,
              'mask-repeat': 'no-repeat',
              'background-color': 'currentColor',
              'vertical-align': 'middle',
              display: 'inline-block',
              width: size,
              height: size,
            };
          },
        },
        { values }
      );
    }),
    plugin(({ addUtilities, theme }) => {
      addUtilities(
        combineValues(
          theme('colors'),
          '.text-decoration',
          'textDecorationColor'
        )
      );
    }),
    plugin(({ addUtilities, theme }) => {
      addUtilities(
        combineValues(
          theme('spacing'),
          '.underline-offset',
          'textUnderlineOffset'
        )
      );
    }),
    plugin(({ addBase }) => {
      addBase({
        '.form-checkbox:checked': {
          backgroundSize: '65% 65%',
          backgroundImage: `url("${svgToDataUri(
            `<svg viewBox="0 0 16 16" fill="none" xmlns="http://www.w3.org/2000/svg">
              <path d="M1 8.22222L6.15789 14L15 1" stroke="white" stroke-linecap="round" stroke-linejoin="round"/>
            </svg>`
          )}")`,
        },
      });
    }),
    plugin(({ addVariant }) =>
      addVariant('drag-item', ['.drag-item&', '.drag-item &'])
    ),
    plugin(({ addVariant }) =>
      addVariant('drag-ghost', ['.drag-ghost&', '.drag-ghost &'])
    ),
  ],
};
