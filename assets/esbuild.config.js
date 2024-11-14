import * as esbuild from 'esbuild';
import { sassPlugin } from 'esbuild-sass-plugin';
import { copy } from 'esbuild-plugin-copy';
import tailwindcss from 'tailwindcss';
import autoprefixer from 'autoprefixer';
import postcss from 'postcss';
import atImport from 'postcss-import';
import chokidar from "chokidar"

const args = process.argv.slice(2);
const watch = args.includes('--watch');
const deploy = args.includes('--deploy');

const loader = {
  ".woff": "file",
  ".svg": "file",
  ".png": "file",
  ".jpg": "file",
  ".jpeg": "file",
  ".css": "css",
};

const plugins = [
  sassPlugin({
    cssImports: true,
    async transform(source, resolveDir) {
      const { css } = await postcss([
        atImport(),
        tailwindcss('./tailwind.config.js'),
        autoprefixer()
      ]).process(source, { from: resolveDir });
      return css;
    }
  }),
  copy({
    resolveFrom: 'cwd',
    assets: [
      {
        from: './static/**/*',
        to: '../priv/static/'
      },
    ],
  }),
];

let opts = {
  entryPoints: ["js/app.js", "css/app.scss"],
  bundle: true,
  logLevel: "info",
  target: "es2017",
  outdir: "../priv/static",
  outbase: ".",
  external: ["*.css", "static/fonts/*", "static/images/*", "static/*"],
  nodePaths: ["../deps"],
  loader: loader,
  plugins: plugins,
  splitting: false,
  format: 'esm',
  entryNames: '[dir]/[name]',
};

if (deploy) {
  opts = {
    ...opts,
    minify: true,
  };
}

if (watch) {
  opts.sourcemap = 'inline';

  const watchDirectories = [
    "../lib/**/*.html.heex",
    "../lib/**/*.ex",
    "./css/**",
    "./js/**",
    "./static/**",
    "./vendor/**",
    "./*.js",
    "./*.json",
  ]

  chokidar.watch(watchDirectories).on('change', async (event, path) => {
    esbuild.build(opts);
  });

} else {
  await esbuild.build(opts);
}
