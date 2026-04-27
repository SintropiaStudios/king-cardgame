import { defineConfig } from 'astro/config';

// https://astro.build/config
export default defineConfig({
  site: 'https://SintropiaStudios.github.io',
  base: '/king-cardgame',
  i18n: {
    defaultLocale: 'pt-br',
    locales: ['pt-br', 'en'],
    routing: {
        prefixDefaultLocale: false
    }
  }
});
