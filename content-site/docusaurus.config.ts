import {readdirSync, readFileSync} from 'node:fs';
import {basename, join} from 'node:path';
import { themes as prismThemes } from 'prism-react-renderer';
import type { Config } from '@docusaurus/types';
import type * as Preset from '@docusaurus/preset-classic';
import { links } from './links';

const isProduction = process.env.NODE_ENV === 'production';
const siteUrl = process.env.SITE_URL || 'https://allanbpediniv.com';
const plausibleSiteDomain = process.env.PLAUSIBLE_SITE_DOMAIN || new URL(siteUrl).hostname;
const openpanelClientId = process.env.OPENPANEL_CLIENT_ID || '';

interface ContentPostMetadata {
  metadata: {
    permalink: string;
    title: string;
    description: string;
    date: string;
    tags: Array<{label: string; permalink: string}>;
  };
}

function parseFrontMatterValue(value: string): string {
  const trimmed = value.trim();

  if (
    (trimmed.startsWith('"') && trimmed.endsWith('"')) ||
    (trimmed.startsWith("'") && trimmed.endsWith("'"))
  ) {
    return trimmed.slice(1, -1);
  }

  return trimmed;
}

function parseMdxFrontMatter(filePath: string): Record<string, string> {
  const source = readFileSync(filePath, 'utf8');
  const match = source.match(/^---\r?\n([\s\S]*?)\r?\n---/);

  if (!match) {
    return {};
  }

  return Object.fromEntries(
    match[1]
      .split(/\r?\n/)
      .map((line) => {
        const separator = line.indexOf(':');

        if (separator === -1) {
          return null;
        }

        return [
          line.slice(0, separator).trim(),
          parseFrontMatterValue(line.slice(separator + 1)),
        ] as const;
      })
      .filter((entry): entry is readonly [string, string] => Boolean(entry)),
  );
}

function deriveSlugFromFilename(fileName: string): string {
  return basename(fileName, '.mdx').replace(/^\d{4}-\d{2}-\d{2}-/, '');
}

function loadContentPosts(sectionPath: string, routeBasePath: string): ContentPostMetadata[] {
  const contentDir = join(__dirname, sectionPath);

  return readdirSync(contentDir)
    .filter((fileName) => fileName.endsWith('.mdx'))
    .map((fileName) => {
      const frontMatter = parseMdxFrontMatter(join(contentDir, fileName));
      const slug = frontMatter.slug || deriveSlugFromFilename(fileName);

      if (!frontMatter.title || !frontMatter.date) {
        throw new Error(`${sectionPath}/${fileName} is missing required title or date frontmatter.`);
      }

      return {
        metadata: {
          permalink: `${routeBasePath}/${slug}`,
          title: frontMatter.title,
          description: frontMatter.description ?? '',
          date: frontMatter.date,
          tags: [],
        },
      };
    })
    .sort(
      (a, b) => Number(new Date(b.metadata.date)) - Number(new Date(a.metadata.date)),
    );
}

const insightPosts = loadContentPosts('insights', '/insights');

const config: Config = {
  title: 'Allan B. Pedin IV',

  favicon: 'img/headshot.png',

  url: siteUrl,
  baseUrl: '/info/',

  projectName: 'abpiv-personal-brand',
  organizationName: 'abpiv',

  trailingSlash: false,

  onBrokenLinks: 'warn',

  future: {
    v4: true,
    faster: false,
  },

  i18n: {
    defaultLocale: 'en',
    locales: ['en'],
  },

  customFields: {
    insightPosts,
    openpanelClientId,
  },

  clientModules: [
    './src/clientModules/mobileSidebarFallback.js',
    './src/clientModules/openpanel.ts',
  ],

  headTags: isProduction && !openpanelClientId
    ? [
        {
          tagName: 'script',
          attributes: {},
          innerHTML:
            'window.plausible=window.plausible||function(){(plausible.q=plausible.q||[]).push(arguments)},plausible.init=plausible.init||function(options){plausible.o=options||{}};plausible.init({endpoint:"/_analytics/api/event"});',
        },
      ]
    : [],

  scripts: isProduction && !openpanelClientId
    ? [
        {
          src: '/_analytics/js/script.js',
          defer: true,
          'data-domain': plausibleSiteDomain,
          'data-api': '/_analytics/api/event',
        },
      ]
    : [],

  presets: [
    [
      'classic',
      {
        docs: {
          routeBasePath: 'none',
          path: 'docs',
          sidebarPath: 'docs/sidebars.js',
        },
        blog: {
          id: 'default',
          routeBasePath: '/insights',
          path: './insights',
          blogTitle: 'Insights',
          blogDescription: 'Posts and ideas -- blog-style.',
          showReadingTime: true,
          authorsMapPath: '../authors.yml',
          feedOptions: {
            type: null,
            title: 'Insights',
          },
          onInlineTags: 'warn',
          onInlineAuthors: 'warn',
          onUntruncatedBlogPosts: 'ignore',
        },
        theme: {
          customCss: './src/css/custom.css',
        },
      } satisfies Preset.Options,
    ],
  ],

  plugins: [
    [
      '@docusaurus/plugin-content-blog',
      {
        id: 'research',
        routeBasePath: '/research',
        path: './research',
        blogTitle: 'Research',
        blogDescription: 'Long-form studies and analyses.',
        showReadingTime: true,
        blogSidebarTitle: 'All research',
        blogSidebarCount: 'ALL',
        authorsMapPath: '../authors.yml',
        feedOptions: {
          type: null,
          title: 'Research',
        },
        onInlineTags: 'warn',
        onInlineAuthors: 'warn',
        onUntruncatedBlogPosts: 'ignore',
      },
    ],
    [
      '@docusaurus/plugin-content-blog',
      {
        id: 'newsroom',
        routeBasePath: '/newsroom',
        path: './newsroom',
        blogTitle: 'Newsroom',
        blogDescription: 'Announcements and milestones.',
        authorsMapPath: '../authors.yml',
        feedOptions: {
          type: null,
          title: 'Newsroom',
        },
        onInlineTags: 'warn',
        onInlineAuthors: 'warn',
        onUntruncatedBlogPosts: 'ignore',
      },
    ],
    [
      './plugins/news-publications-feed',
      {
        feedPath: 'news-publications/rss.xml',
        title: 'News & Publications',
        description: 'Research papers, launch notes, and project milestones from Allan B. Pedin IV.',
      },
    ],
    [
      '@easyops-cn/docusaurus-search-local',
      {
        hashed: true,
        indexBlog: true,
        indexPages: true,
        blogRouteBasePath: ['/research', '/insights', '/newsroom'],
      },
    ],
  ],

  themeConfig: {
    image: 'img/social-card.png',
    colorMode: {
      defaultMode: 'dark',
      disableSwitch: true,
      respectPrefersColorScheme: false,
    },
    navbar: {
      title: 'ABPIV',
      logo: {
        alt: 'Allan B. Pedin IV',
        src: 'img/headshot.png',
        srcDark: 'img/headshot.png',
      },
      items: [
        {
          to: '/insights',
          label: 'Insights',
          position: 'left',
        },
        {
          to: '/news-publications',
          label: 'News & Publications',
          position: 'left',
        },
        {
          to: '/featured',
          label: 'Featured On',
          position: 'left',
        },
      ],
    },
    footer: {
      style: 'dark',
      links: [
        {
          title: 'Navigation',
          items: [
            { to: '/insights', label: 'Insights' },
            { to: '/news-publications', label: 'News & Publications' },
            { to: '/featured', label: 'Featured On' },
          ],
        },
        {
          title: 'RSS Feed',
          items: [
            { to: '/news-publications/rss.xml', label: 'News & Publications' },
          ],
        },
      ],
      copyright: 'Copyright (c) ' + new Date().getFullYear() + ' Allan B. Pedin IV.',
    },
    prism: {
      theme: prismThemes.github,
      darkTheme: prismThemes.dracula,
    },
  } satisfies Preset.ThemeConfig,
};

export default config;
