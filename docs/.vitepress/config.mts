import { defineConfig } from 'vitepress'

export default defineConfig({
  title: 'pepper',
  description: 'High-performance in-memory caching for Dart servers',
  base: '/',
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
      {
        icon: {
          svg: '<svg width="20" height="20" viewBox="0 0 68 70" xmlns="http://www.w3.org/2000/svg"><path d="M13.8762,54.1795 L2.2392,42.5365 C0.8382,41.0965 0.0372,39.1765 0.0002,37.1665 C0.1042,36.0755 0.4062,35.0125 0.8912,34.0305 L11.6552,11.6415 L13.8762,54.1795 Z" fill="currentColor" fill-opacity="0.45"/><path d="M53.7287,13.887 L42.0857,2.244 C41.0747,1.227 38.9557,0.005 37.1617,0.005 C35.7647,-0.043 34.3787,0.265 33.1347,0.902 L11.6547,11.641 L53.7287,13.887 Z" fill="currentColor"/><polygon fill="currentColor" points="27.7585 68.0613 55.9685 68.0613 55.9685 55.9673 34.9225 49.2543 15.6755 55.9673"/><path d="M11.655,47.9124 C11.655,51.5244 12.106,52.3914 13.894,54.1854 L15.7,55.9914 L55.992,55.9914 L36.271,33.5904 L11.655,11.6474 L11.655,47.9124 Z" fill="currentColor" fill-opacity="0.7"/><path d="M47.4557,11.6414 L11.6547,11.6414 L55.9797,55.9674 L68.0687,55.9674 L68.0687,28.2084 L53.7287,13.8874 C51.7177,11.8644 49.9307,11.6414 47.4557,11.6414" fill="currentColor" fill-opacity="0.45"/><path d="M14.3278,54.6306 C12.5218,52.8246 12.0878,51.0606 12.0878,47.9126 L12.0878,12.0926 L11.6548,11.6416 L11.6548,47.9066 C11.6548,51.0606 11.6548,51.9276 14.3458,54.6306 L15.6938,55.9736 L14.3278,54.6306 Z" fill="#FFFFFF" fill-opacity="0.85"/><polygon fill="currentColor" fill-opacity="0.45" points="67.611 27.7634 67.611 55.5214 55.517 55.5214 55.968 55.9674 68.063 55.9674 68.063 28.2144"/><path d="M53.7287,13.887 C51.5077,11.666 49.6897,11.641 47.0107,11.641 L11.6547,11.641 L12.1057,12.093 L47.0227,12.093 C48.3537,12.093 51.7297,11.87 53.7347,13.899 L53.7287,13.887 Z" fill="#FFFFFF" fill-opacity="0.85"/></svg>',
        },
        link: 'https://pub.dev/packages/pepper',
        ariaLabel: 'pepper on pub.dev',
      },
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
