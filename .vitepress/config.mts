import { defineConfig } from 'vitepress'

export default defineConfig({
  title: 'pepper',
  description: 'High-performance in-memory caching for Dart servers',
  base: '/',
  srcDir: 'docs',
  srcExclude: ['README.md'],
  cleanUrls: true,
  lastUpdated: true,
  head: [
    ['link', { rel: 'icon', type: 'image/svg+xml', href: '/logo.svg' }],
    ['meta', { name: 'theme-color', content: '#d9483b' }],
  ],
  markdown: {
    lineNumbers: true,
  },
  themeConfig: {
    logo: '/logo.svg',
    nav: [
      { text: 'Introduction', link: '/introduction', activeMatch: '^/introduction' },
      { text: 'Get Started', link: '/get-started', activeMatch: '^/get-started' },
      { text: 'Eviction', link: '/eviction/', activeMatch: '^/eviction/' },
      { text: 'Example', link: '/example', activeMatch: '^/example' },
      { text: 'Changelog', link: '/changelog', activeMatch: '^/changelog' },
    ],
    sidebar: [
      { text: 'Introduction', link: '/introduction' },
      { text: 'Get Started', link: '/get-started' },
      {
        text: 'Eviction Techniques',
        items: [
          { text: 'Overview', link: '/eviction/' },
          { text: 'LRU — Least Recently Used', link: '/eviction/lru' },
          { text: 'LFU — Least Frequently Used', link: '/eviction/lfu' },
          { text: 'FIFO — First In, First Out', link: '/eviction/fifo' },
        ],
      },
      { text: 'Example', link: '/example' },
      { text: 'Changelog', link: '/changelog' },
    ],
    socialLinks: [
      { icon: 'github', link: 'https://github.com/infm5/pepper' },
    ],
    search: {
      provider: 'local',
    },
    editLink: {
      pattern: 'https://github.com/infm5/pepper/edit/master/docs/:path',
      text: 'Edit this page on GitHub',
    },
    outline: {
      level: [2, 3],
      label: 'On this page',
    },
    footer: {
      message: 'Documentation built with VitePress',
      copyright: 'Copyright © 2026 Deepraj Baidya',
    },
  },
})
