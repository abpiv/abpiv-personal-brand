const ANALYTICS_PREFIX = "/_analytics";
const SCRIPT_ROUTE = `${ANALYTICS_PREFIX}/js/script.js`;
const EVENT_ROUTE = `${ANALYTICS_PREFIX}/api/event`;
const OPENPANEL_ROUTE = `${ANALYTICS_PREFIX}/openpanel/track`;
const OPENPANEL_ORIGIN = 'https://openpanel-ingest.lobst3rs.com';
const OPENPANEL_SITES = new Set([
    'https://allanbpediniv.com',
    'https://content-site.lobst3rs.com',
]);
const PRESERVED_REQUEST_HEADERS = [
    "user-agent",
    "x-forwarded-for",
    "accept-language",
    "referer",
];
function textResponse(message, status) {
    return new Response(message, {
        status,
        headers: {
            "content-type": "text/plain; charset=utf-8",
            "cache-control": "no-store",
        },
    });
}
function getOriginHostname(env) {
    const hostname = env.PLAUSIBLE_ORIGIN_HOSTNAME.trim();
    if (!hostname || hostname.includes("/") || hostname.includes(":")) {
        throw new Error("Invalid Plausible origin hostname binding");
    }
    return hostname;
}
function copyVisitorHeaders(from, to) {
    for (const header of PRESERVED_REQUEST_HEADERS) {
        const value = from.get(header);
        if (value !== null) {
            to.set(header, value);
        }
    }
}
function buildHeaders(request) {
    const headers = new Headers();
    copyVisitorHeaders(request.headers, headers);
    const contentType = request.headers.get("content-type");
    if (contentType !== null) {
        headers.set("content-type", contentType);
    }
    return headers;
}
function addAccessServiceTokenHeaders(headers, env) {
    const clientId = env.CF_ACCESS_CLIENT_ID?.trim();
    const clientSecret = env.CF_ACCESS_CLIENT_SECRET?.trim();
    if (clientId && clientSecret) {
        headers.set("CF-Access-Client-Id", clientId);
        headers.set("CF-Access-Client-Secret", clientSecret);
    }
}
async function sanitizeResponse(upstream, originHostname, publicHostname) {
    const headers = new Headers(upstream.headers);
    const location = headers.get("location");
    if (location !== null) {
        headers.delete("location");
    }
    const body = await upstream.text();
    return new Response(body.replaceAll(originHostname, publicHostname), {
        status: upstream.status,
        statusText: upstream.statusText,
        headers,
    });
}
async function proxyScript(request, env, originHostname) {
    const headers = buildHeaders(request);
    addAccessServiceTokenHeaders(headers, env);
    const upstreamRequest = new Request(`https://${originHostname}/js/script.js`, {
        method: "GET",
        headers,
        redirect: "manual",
    });
    return fetch(upstreamRequest);
}
async function proxyEvent(request, env, originHostname) {
    const headers = buildHeaders(request);
    addAccessServiceTokenHeaders(headers, env);
    const body = await request.arrayBuffer();
    const upstreamRequest = new Request(`https://${originHostname}/api/event`, {
        method: "POST",
        headers,
        body,
        redirect: "manual",
    });
    return fetch(upstreamRequest);
}
async function proxyOpenPanel(request, url) {
    const deviceId = url.pathname === `${OPENPANEL_ROUTE}/device-id`;
    if (request.method !== (deviceId ? 'GET' : 'POST')) {
        return textResponse('Method not allowed', 405);
    }
    if (!OPENPANEL_SITES.has(url.origin) ||
        (request.headers.has('origin') && request.headers.get('origin') !== url.origin) ||
        request.headers.get('sec-fetch-site') === 'cross-site') {
        return textResponse('Forbidden', 403);
    }
    const clientId = request.headers.get('openpanel-client-id');
    if (!clientId || request.headers.has('openpanel-client-secret')) {
        return textResponse('Forbidden', 403);
    }
    // Forward only collection metadata; never site cookies, Authorization,
    // Access credentials, or caller-supplied IP overrides.
    const headers = new Headers({ 'origin': url.origin, 'openpanel-client-id': clientId });
    for (const name of ['user-agent', 'openpanel-sdk-name', 'openpanel-sdk-version',
        'openpanel-device-id', 'openpanel-session-id']) {
        const value = request.headers.get(name);
        if (value)
            headers.set(name, value);
    }
    headers.set('referer', `${url.origin}/`);
    headers.set('content-type', 'application/json');
    let body;
    if (!deviceId) {
        const reader = request.body?.getReader();
        if (!reader)
            return textResponse('Invalid event', 400);
        const chunks = [];
        let size = 0;
        while (true) {
            const { done, value } = await reader.read();
            if (done)
                break;
            size += value.byteLength;
            if (size > 262144) {
                await reader.cancel();
                return textResponse('Event too large', 413);
            }
            chunks.push(value);
        }
        const bytes = new Uint8Array(size);
        let offset = 0;
        for (const chunk of chunks) {
            bytes.set(chunk, offset);
            offset += chunk.byteLength;
        }
        let event;
        try {
            event = JSON.parse(new TextDecoder().decode(bytes));
        }
        catch {
            return textResponse('Invalid event', 400);
        }
        if (!event || event.type !== 'track' || !event.payload ||
            typeof event.payload !== 'object' || Array.isArray(event.payload) ||
            'clientSecret' in event || ('clientId' in event && event.clientId !== clientId)) {
            return textResponse('Forbidden', 403);
        }
        body = JSON.stringify({ type: 'track', payload: event.payload });
    }
    const upstream = await fetch(new Request(`${OPENPANEL_ORIGIN}/api/track${deviceId ? '/device-id' : ''}`, { method: request.method, headers, body, redirect: 'manual', signal: AbortSignal.timeout(15000) }));
    if (upstream.status >= 300 && upstream.status < 400) {
        return textResponse('Analytics unavailable', 502);
    }
    if (!upstream.ok)
        return textResponse('Analytics unavailable', upstream.status);
    return new Response(upstream.body, {
        status: upstream.status,
        headers: { 'content-type': 'application/json', 'cache-control': 'no-store' },
    });
}
export default {
    async fetch(request, env) {
        const url = new URL(request.url);
        try {
            if (url.pathname === OPENPANEL_ROUTE || url.pathname === `${OPENPANEL_ROUTE}/device-id`) {
                return await proxyOpenPanel(request, url);
            }
            const originHostname = getOriginHostname(env);
            let upstream;
            if (url.pathname === SCRIPT_ROUTE) {
                if (request.method !== "GET") {
                    return textResponse("Method not allowed", 405);
                }
                upstream = await proxyScript(request, env, originHostname);
            }
            else if (url.pathname === EVENT_ROUTE) {
                if (request.method !== "POST") {
                    return textResponse("Method not allowed", 405);
                }
                upstream = await proxyEvent(request, env, originHostname);
            }
            else {
                return textResponse("Not found", 404);
            }
            return sanitizeResponse(upstream, originHostname, url.hostname);
        }
        catch {
            return textResponse("Analytics proxy error", 502);
        }
    },
};
