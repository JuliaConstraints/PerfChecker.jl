import { defineConfig } from 'vitepress'
import { tabsMarkdownPlugin } from 'vitepress-plugin-tabs'
import footnote from 'markdown-it-footnote'

export default defineConfig({
  base: 'REPLACE_ME_DOCUMENTER_VITEPRESS',
  title: 'REPLACE_ME_DOCUMENTER_VITEPRESS',
  description: 'REPLACE_ME_DOCUMENTER_VITEPRESS',
  outDir: 'REPLACE_ME_DOCUMENTER_VITEPRESS',
  lastUpdated: true,
  cleanUrls: true,
  ignoreDeadLinks: false,
  markdown: {
    config(md) {
      md.use(tabsMarkdownPlugin)
      md.use(footnote)
    },
    theme: { light: 'github-light', dark: 'github-dark' },
  },
  themeConfig: {
    outline: { level: 'deep', label: 'On this page' },
    search: {
      provider: 'local',
      options: { detailedView: true },
    },
    nav: 'REPLACE_ME_DOCUMENTER_VITEPRESS',
    sidebar: 'REPLACE_ME_DOCUMENTER_VITEPRESS',
    editLink: 'REPLACE_ME_DOCUMENTER_VITEPRESS',
    socialLinks: [
      { icon: 'github', link: 'https://github.com/Mirage-Interactive-Fr/PerfChecker.jl' },
    ],
    footer: {
      message: 'PerfChecker is open-source software maintained by <a href="https://mirageinteractive.fr/">Mirage Interactive</a>.',
      copyright: `© ${new Date().getUTCFullYear()} Mirage Interactive and PerfChecker contributors`,
    },
  },
})
