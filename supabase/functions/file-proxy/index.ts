const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, range, if-range',
  'Access-Control-Allow-Methods': 'GET, HEAD, OPTIONS',
  'Access-Control-Expose-Headers': 'accept-ranges, content-length, content-range, content-type, content-disposition, etag, last-modified',
};

const ALLOWED_HOSTS = new Set([
  'inscricoes.led.globo',
]);

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      ...CORS_HEADERS,
      'Content-Type': 'application/json; charset=utf-8',
      'Cache-Control': 'no-store',
    },
  });
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: CORS_HEADERS });
  }

  if (req.method !== 'GET' && req.method !== 'HEAD') {
    return json({ error: 'method_not_allowed' }, 405);
  }

  const requestUrl = new URL(req.url);
  const target = requestUrl.searchParams.get('url') || '';

  if (!target) {
    return json({ error: 'missing_url' }, 400);
  }

  let parsedTarget: URL;
  try {
    parsedTarget = new URL(target);
  } catch {
    return json({ error: 'invalid_url' }, 400);
  }

  if (parsedTarget.protocol !== 'https:') {
    return json({ error: 'invalid_protocol' }, 400);
  }

  if (!ALLOWED_HOSTS.has(parsedTarget.hostname)) {
    return json({ error: 'host_not_allowed', host: parsedTarget.hostname }, 403);
  }

  const range = req.headers.get('range');
  const ifRange = req.headers.get('if-range');

  const upstreamHeaders = new Headers({
    'User-Agent': 'PPA2026-FileProxy/1.0',
    'Accept': 'application/pdf,video/mp4,application/octet-stream,*/*',
  });
  if (range) upstreamHeaders.set('Range', range);
  if (ifRange) upstreamHeaders.set('If-Range', ifRange);

  const upstream = await fetch(parsedTarget.toString(), {
    method: req.method,
    redirect: 'follow',
    headers: upstreamHeaders,
  });

  if (!upstream.ok) {
    return json({ error: 'upstream_failed', status: upstream.status }, upstream.status || 502);
  }

  const contentType = upstream.headers.get('content-type') || 'application/octet-stream';
  const contentLength = upstream.headers.get('content-length');
  const lastModified = upstream.headers.get('last-modified');
  const etag = upstream.headers.get('etag');
  const contentRange = upstream.headers.get('content-range');
  const acceptRanges = upstream.headers.get('accept-ranges');

  const headers = new Headers(CORS_HEADERS);
  headers.set('Content-Type', contentType);
  headers.set('Content-Disposition', 'inline');
  headers.set('Cache-Control', 'public, max-age=300');
  if (contentLength) headers.set('Content-Length', contentLength);
  if (lastModified) headers.set('Last-Modified', lastModified);
  if (etag) headers.set('ETag', etag);
  if (contentRange) headers.set('Content-Range', contentRange);
  if (acceptRanges) {
    headers.set('Accept-Ranges', acceptRanges);
  } else if (contentRange || contentType.startsWith('video/')) {
    headers.set('Accept-Ranges', 'bytes');
  }

  return new Response(upstream.body, {
    status: upstream.status,
    headers,
  });
});
