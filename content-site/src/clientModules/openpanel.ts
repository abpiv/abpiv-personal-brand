import ExecutionEnvironment from '@docusaurus/ExecutionEnvironment';
import siteConfig from '@generated/docusaurus.config';
import {OpenPanel} from '@openpanel/web';
import type {ClientModule} from '@docusaurus/types';

const clientId = siteConfig.customFields?.openpanelClientId;
let openpanel: OpenPanel | undefined;
let pendingView: number | undefined;

// Only the intended deployed origin reports visits. Local builds and Pages
// artifact URLs must not contaminate the website's analytics.
if (
  process.env.NODE_ENV === 'production' &&
  ExecutionEnvironment.canUseDOM &&
  window.location.origin === new URL(siteConfig.url).origin &&
  typeof clientId === 'string' &&
  clientId
) {
  openpanel = new OpenPanel({
    clientId,
    apiUrl: `${window.location.origin}/_analytics/openpanel`,
    trackScreenViews: false,
    trackOutgoingLinks: true,
    trackAttributes: false,
    filter(event) {
      if (event.type !== 'track') return false;
      // Keep campaign attribution, but omit fragments, search text and other
      // arbitrary query parameters from page, referrer and outbound URLs.
      for (const key of ['__path', '__referrer', 'href']) {
        const value = event.payload.properties?.[key];
        if (typeof value !== 'string' || !value) continue;
        try {
          const url = new URL(value);
          const campaign = new URLSearchParams();
          if (key === '__path') {
            for (const name of ['utm_source', 'utm_medium', 'utm_campaign', 'utm_term', 'utm_content']) {
              const item = url.searchParams.get(name);
              if (item) campaign.set(name, item);
            }
          }
          url.search = campaign.toString();
          url.hash = '';
          event.payload.properties![key] = url.toString();
        } catch {
          delete event.payload.properties![key];
        }
      }
      return true;
    },
  });
}

export const onRouteDidUpdate: ClientModule['onRouteDidUpdate'] = ({location, previousLocation}) => {
  if (!openpanel || (previousLocation?.pathname === location.pathname &&
      previousLocation?.search === location.search)) return;
  if (pendingView !== undefined) window.cancelAnimationFrame(pendingView);
  // Docusaurus updates the rendered route before this hook; wait for its head
  // update so the event contains the destination title, not the previous one.
  pendingView = window.requestAnimationFrame(() => {
    pendingView = undefined;
    openpanel?.screenView();
  });
};
