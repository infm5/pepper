### Documentation site

The guides live in `docs/` and are built with VitePress:

```sh
cd docs
npm install
npm run docs:dev    # local preview
npm run docs:build  # production build in docs/.vitepress/dist
```

The site is deployed with **Cloudflare Pages**:

- Root directory: `docs`
- Build command: `npm run docs:build`
- Build output directory: `.vitepress/dist` (relative to `docs`)

The site is served at the domain root (`base: '/'`). Pushes to `master`
deploy automatically. The `docs/wrangler.toml` file also supports manual
deploys with `npx wrangler pages deploy .vitepress/dist`.

The test suite covers the eviction contract for every algorithm, the full
facade API, TTL/jitter/janitor behaviour on a fake clock, loader concurrency
and error semantics, negative caching in both modes, metrics, warm-up, copy
hooks, and randomized fuzzing against reference models. Line coverage is
100%.
