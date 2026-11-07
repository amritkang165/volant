// Currency rates for the /try demo, mirroring Volant's VolantRatesHost: three fixed upstream URLs
// (the same ones the app uses), no input from the visitor except which feed, no redirects, a size
// cap, a shape check before replying, and edge caching so most visits never reach the providers.
// The upstream request carries no visitor headers, IP-derived data or query text, and nothing
// here is logged. VolantCore's own parsers, running in the visitor's browser, validate the body again.

type Feed = { url: string; seconds: number; maximumBytes: number; valid: (text: string) => boolean };

/** Parses JSON or returns null, for the shape checks. */
function json(text: string): Record<string, unknown> | null {
  try {
    const value: unknown = JSON.parse(text);
    return value && typeof value === 'object' && !Array.isArray(value) ? (value as Record<string, unknown>) : null;
  } catch {
    return null;
  }
}

const coins = ['bitcoin', 'ethereum', 'solana', 'ripple', 'binancecoin', 'cardano', 'dogecoin', 'tether', 'usd-coin', 'litecoin', 'polkadot', 'tron'];

const feeds: Record<string, Feed> = {
  ecb: {
    url: 'https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml',
    seconds: 4 * 3600,
    maximumBytes: 65536,
    valid: (text) => /<Cube\s+time=['"]\d{4}-\d{2}-\d{2}['"]/.test(text) && (text.match(/currency=['"][A-Z]{3}['"]/g) ?? []).length >= 5,
  },
  world: {
    url: 'https://open.er-api.com/v6/latest/EUR',
    seconds: 3600,
    maximumBytes: 32768,
    valid: (text) => {
      const body = json(text);
      return body?.result === 'success' && body.base_code === 'EUR' && typeof body.rates === 'object';
    },
  },
  crypto: {
    url: `https://api.coingecko.com/api/v3/simple/price?ids=${coins.join(',')}&vs_currencies=eur`,
    seconds: 60,
    maximumBytes: 16384,
    valid: (text) => {
      const body = json(text);
      return !!body && coins.filter((id) => typeof (body[id] as { eur?: unknown } | undefined)?.eur === 'number').length * 2 >= coins.length;
    },
  },
};

/** The Workers edge cache when running on Cloudflare; undefined in other runtimes. */
function edgeCache(): Cache | undefined {
  const storage = (globalThis as { caches?: CacheStorage & { default?: Cache } }).caches;
  return storage?.default;
}

/** Fetches one fixed feed without following redirects, capped in size and checked for shape. */
async function fetchFeed(feed: Feed): Promise<{ body: string; fetchedAt: number } | null> {
  const response = await fetch(feed.url, {
    redirect: 'manual',
    headers: { Accept: feed.url.endsWith('.xml') ? 'application/xml' : 'application/json', 'User-Agent': 'usevolant.com try demo' },
  });
  if (response.status !== 200) return null;
  const declared = Number(response.headers.get('content-length') ?? '0');
  if (declared > feed.maximumBytes) return null;
  const bytes = new Uint8Array(await response.arrayBuffer());
  if (bytes.length > feed.maximumBytes) return null;
  const body = new TextDecoder('utf-8', { fatal: false }).decode(bytes);
  return feed.valid(body) ? { body, fetchedAt: Math.floor(Date.now() / 1000) } : null;
}

/** Answers GET /try/rates/{ecb|world|crypto} from the edge cache or one upstream fetch. */
export async function GET(_request: Request, context: { params: Promise<{ feed: string }> }) {
  const { feed: name } = await context.params;
  const feed = Object.hasOwn(feeds, name) ? feeds[name] : undefined;
  if (!feed) return new Response('Unknown feed', { status: 404 });
  const cache = edgeCache();
  const key = new Request(`https://usevolant.com/try/rates/${name}`);
  const cached = await cache?.match(key);
  if (cached) return cached;
  let fetched: { body: string; fetchedAt: number } | null = null;
  try {
    fetched = await fetchFeed(feed);
  } catch {
    fetched = null;
  }
  if (!fetched) return new Response('Rates unavailable', { status: 502, headers: { 'Cache-Control': 'no-store' } });
  const response = new Response(fetched.body, {
    headers: {
      'Content-Type': name === 'ecb' ? 'application/xml; charset=utf-8' : 'application/json; charset=utf-8',
      'Cache-Control': `public, max-age=${feed.seconds}`,
      'X-Volant-Fetched-At': String(fetched.fetchedAt),
    },
  });
  await cache?.put(key, response.clone());
  return response;
}
