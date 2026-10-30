import {afterEach, beforeEach, describe, expect, it, vi} from 'vitest';
import worker from '../src/index';

const env = {PLAUSIBLE_ORIGIN_HOSTNAME: 'analytics.lobst3rs.com'};
const path = 'https://allanbpediniv.com/_analytics/openpanel/track';
const event = {type: 'track', payload: {name: 'screen_view', properties: {__path: 'https://allanbpediniv.com/info/'}}};
function post(body = event, headers: Record<string, string> = {}) {
  return new Request(path, {method: 'POST', body: JSON.stringify(body), headers: {
    'origin': 'https://allanbpediniv.com', 'openpanel-client-id': 'website-client', ...headers,
  }});
}

describe('OpenPanel same-origin collection', () => {
  beforeEach(() => vi.stubGlobal('fetch', vi.fn(async () => new Response('{"deviceId":"visitor"}', {
    headers: {'set-cookie': 'unwanted=1', 'location': 'https://private.example'},
  }))));
  afterEach(() => vi.unstubAllGlobals());

  it('delivers website events without forwarding authentication or IP overrides', async () => {
    const response = await worker.fetch(post(event, {
      'cookie': 'private-session', 'authorization': 'Bearer private',
      'cf-access-client-secret': 'private', 'x-client-ip': '203.0.113.9',
      'user-agent': 'Mozilla/5.0 Test Browser',
    }), env);
    const upstream = vi.mocked(fetch).mock.calls[0][0] as Request;
    expect(upstream.url).toBe('https://openpanel-ingest.lobst3rs.com/api/track');
    expect(await upstream.json()).toEqual(event);
    expect(upstream.headers.get('origin')).toBe('https://allanbpediniv.com');
    expect(upstream.headers.get('user-agent')).toBe('Mozilla/5.0 Test Browser');
    for (const header of ['cookie', 'authorization', 'cf-access-client-secret', 'x-client-ip']) {
      expect(upstream.headers.has(header)).toBe(false);
    }
    expect(response.status).toBe(200);
    expect(response.headers.has('set-cookie')).toBe(false);
    expect(response.headers.has('location')).toBe(false);
    expect(response.headers.get('cache-control')).toBe('no-store');
  });

  it('supports only the device-id read operation and drops arbitrary queries', async () => {
    const response = await worker.fetch(new Request(path + '/device-id?secret=ignored', {
      headers: {'openpanel-client-id': 'website-client'},
    }), env);
    expect(response.status).toBe(200);
    const upstream = vi.mocked(fetch).mock.calls[0][0] as Request;
    expect(upstream.url).toBe('https://openpanel-ingest.lobst3rs.com/api/track/device-id');
  });

  it('rejects cross-site events, non-tracking operations and credential overrides', async () => {
    const requests = [
      post(event, {origin: 'https://unrelated.example'}),
      post(event, {'sec-fetch-site': 'cross-site'}),
      post(event, {'openpanel-client-secret': 'private'}),
      post({...event, type: 'identify'}),
      post({...event, clientSecret: 'private'} as typeof event),
      post({...event, clientId: 'different-client'} as typeof event),
      new Request(path.replace('allanbpediniv.com', 'unrelated.example'), {
        method: 'POST', body: JSON.stringify(event), headers: {'openpanel-client-id': 'website-client'},
      }),
    ];
    for (const request of requests) expect((await worker.fetch(request, env)).status).toBe(403);
    expect(fetch).not.toHaveBeenCalled();
  });

  it('rejects malformed, oversized and unsupported requests before forwarding', async () => {
    const headers = {'openpanel-client-id': 'website-client'};
    expect((await worker.fetch(new Request(path, {method: 'POST', body: '{', headers}), env)).status).toBe(400);
    expect((await worker.fetch(new Request(path, {method: 'POST', body: 'x'.repeat(262145), headers}), env)).status).toBe(413);
    expect((await worker.fetch(new Request(path, {headers}), env)).status).toBe(405);
    expect((await worker.fetch(new Request(path + '/admin', {headers}), env)).status).toBe(404);
    expect(fetch).not.toHaveBeenCalled();
  });

  it('does not expose upstream redirects or diagnostic bodies', async () => {
    vi.mocked(fetch).mockResolvedValueOnce(new Response('private origin', {status: 302, headers: {location: '/login'}}));
    const redirect = await worker.fetch(post(), env);
    expect(redirect.status).toBe(502);
    expect(await redirect.text()).toBe('Analytics unavailable');
    vi.mocked(fetch).mockResolvedValueOnce(new Response('private diagnostic', {status: 503}));
    const failure = await worker.fetch(post(), env);
    expect(failure.status).toBe(503);
    expect(await failure.text()).toBe('Analytics unavailable');
  });
});
