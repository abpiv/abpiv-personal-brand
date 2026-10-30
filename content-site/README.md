# Personal Brand Content Site - Documentation

## Overview

This is a Docusaurus v3 (TypeScript) personal brand site located in `content-site/`. It serves as a hub for showcasing work across multiple content sections.

For the optional OpenPanel integration, environment configuration, and activation
checks, see [OPENPANEL.md](OPENPANEL.md).

---

## Architecture

### Routes & Plugins

| Route                | Plugin                                             | Notes                                                                 |
| -------------------- | -------------------------------------------------- | --------------------------------------------------------------------- |
| `/research`          | `@docusaurus/plugin-content-blog` (id: `research`) | Long-form research; feed output is disabled here                      |
| `/insights`          | `@docusaurus/plugin-content-blog` (id: `default`)  | Blog-style posts; feed output is disabled here                        |
| `/newsroom`          | `@docusaurus/plugin-content-blog` (id: `newsroom`) | Announcements; feed output is disabled here                           |
| `/news-publications` | Custom React page `src/pages/news-publications/`   | Combined newsroom + research listing; RSS at `/news-publications/rss.xml` |
| `/featured`          | Custom React page `src/pages/featured/index.tsx`   | Showcase of appearances                                               |
| `/about`             | MDX page `src/pages/about.mdx`                     | Bio page                                                              |
| `/`                  | Custom `src/pages/index.tsx`                       | Homepage with Hero, SectionCards, LatestPosts                         |

### Key Files

- **`docusaurus.config.ts`** - Main configuration. All social links are imported from `links.ts`. Footer displays navigation + RSS links only. Social icons are rendered via swizzled Footer component.
- **`links.ts`** - Single source of truth for all social/website URLs. Contains: github, linkedin, x, facebook, instagram, youtube, hackernoon, hackernews, crunchbase, f6s, strava, tiktok, email
- **`plugins/news-publications-feed/index.js`** - Emits the single combined News & Publications RSS feed from `newsroom/` and `research/`.
- **`src/utils/contentPosts.ts`** - Shared helpers for loading and merging blog-instance content.
- **`src/theme/Footer/index.tsx`** - Ejected and customized Footer. Replaces standard footer links with a centered row of social icons using FontAwesome. Uses `@fortawesome/react-fontawesome` package.
- **`src/css/custom.css`** - Dark theme with electric blue (`#00AAFF`) primary color. Dark-only mode (no theme switching).

---

## Custom Components

### `src/components/`
- **HomeHero** - Hero section on homepage with Allan's CEO narrative, research credentials, founder work, and core thesis.
- **SectionCards** - Cards for Insights, News & Publications, and Featured On
- **LatestPosts** - Shows recent insights, the combined News & Publications stream, and featured appearances
- **FeaturedFilters** - Tag multi-select + search bar for featured page
- **FeaturedCard** - Card component for featured items

### `src/data/`
- **featured.ts** - Featured items array with YouTube videos. Uses `hqdefault.jpg` thumbnails from YouTube image service. Each item has: title, outlet, description, preview (image URL), website (link), tags, date
- **featuredTags.ts** - Tag definitions: podcast, interview, article, guest-post, talk, keynote, video, panel, newsletter, book, favorite

---

## Content Sections

### News & Publications Feed
- One RSS feed is generated at `/news-publications/rss.xml`.
- The feed combines `newsroom/` and `research/` entries.
- Individual `/insights/rss.xml`, `/newsroom/rss.xml`, and `/research/rss.xml` feeds are disabled in `docusaurus.config.ts`.

### Research (`research/` directory)
- Blog-style posts for published research
- Currently contains 3 published papers:
  1. "Secure Digital Voting" - ACM 2023, CNU
  2. "Digital Asset Ownership" - ACM 2023, CNU
  3. "Predicting Road Quality Using High Resolution Satellite Imagery" - PLOS ONE 2021, William & Mary (under Ethan Brewer)

### Insights (`insights/` directory)
- General blog posts
- Currently has 1 seed post

### Newsroom (`newsroom/` directory)
- Announcements and milestones
- Currently has 1 seed post

---

## Author System

All three blog directories (`research/`, `insights/`, `newsroom/`) each have an `authors.yml` file that defines the `allan` author:
```yaml
allan:
  name: "Allan B. Pedin IV"
  title: "Software Engineer & Developer"
  url: "https://abpiv.dev"
  image_url: "/img/headshot.png"
  socials:
    github: "BrewDogDev"
    x: "allanpedin"
    linkedin: "allanpedin"
```

All blog posts frontmatter should use `author: allan`.

---

## Deployment

- **baseUrl**: `/info/`
- **url**: defaults to the production `SITE_URL` value, `https://allanbpediniv.com`
- Preview branch: `preview`
- Preview URL: `https://content-site.lobst3rs.com/info/`
- Production branch: `main`
- Production URL: `https://allanbpediniv.com/info/`
- Production domain discovery: use the live domain that returns `200`; apex `allanbpediniv.com` is the current chosen production domain because `www.allanbpediniv.com` did not resolve during discovery.
- Production deploys: manual `Content Site` workflow dispatch from `main` with `target=production`
- GitHub Actions workflow in `.github/workflows/deploy.yml` runs content-site CI, preview auto-deploys, and manual production deploys to Cloudflare Pages.
- Preview analytics collection uses `PLAUSIBLE_SITE_DOMAIN=content-site.lobst3rs.com` and same-origin `/_analytics/*` paths, but the current analytics infrastructure only provisions `allanbpediniv.com/_analytics/*`. Extend the separate analytics infrastructure/route before expecting preview analytics collection.
- Cloudflare Pages project: `abpiv-personal-brand`
- See [`AI_HANDOFF.md`](./AI_HANDOFF.md) for the current deployment architecture, packaging details, credentials, and verification commands.

---

## Build Commands

```bash
cd content-site
npm start        # Development server on http://localhost:3001
npm run build    # Production build
npm run serve    # Serve built site
npm run clear    # Clear cache
```

---

## Known Issues / Notes

- `blogDir` warning refers to old default path - harmless
- Dark-only theme enforced via `colorMode.disableSwitch: true`
- Social icons in footer use `@fortawesome/react-fontawesome` (brands + solid packages installed)

---

## Adding Content

### New Featured Item
Add to `src/data/featured.ts`:
```typescript
{
  title: 'Video Title',
  outlet: 'Channel Name',
  description: 'Brief description.',
  preview: 'https://i.ytimg.com/vi/[VIDEO_ID]/hqdefault.jpg',
  website: 'https://youtube.com/watch?v=[VIDEO_ID]',
  tags: ['podcast', 'video'],
  date: '2025-MM-DD',
}
```

### New Research Post
Create new file in `research/` directory with frontmatter:
```yaml
---
slug: url-friendly-slug
title: "Post Title"
author: allan
tags: [research]
date: 2025-MM-DD
description: "Brief description for SEO"
---
```

### Update Social Links
Edit `links.ts` - changes automatically propagate to footer icons and navbar.

---

## Theme Customization

- **Primary color**: Electric blue `#00AAFF` (light mode: `#0066FF`)
- **Background**: Dark `#0d1117`
- **Surface**: `#161b22`
- **Font**: system-ui

All changes made in `src/css/custom.css`
