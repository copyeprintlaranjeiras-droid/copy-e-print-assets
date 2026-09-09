const allowedOrigins = new Set([
  'https://www.copyeprint.com.br',
  'https://copyeprint.com.br'
]);

export default async function handler(request, response) {
  const origin = request.headers.origin || '';
  if (allowedOrigins.has(origin)) response.setHeader('Access-Control-Allow-Origin', origin);
  response.setHeader('Vary', 'Origin');
  response.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
  response.setHeader('Cache-Control', 's-maxage=900, stale-while-revalidate=86400');

  if (request.method === 'OPTIONS') return response.status(204).end();
  if (request.method !== 'GET') return response.status(405).json({ error: 'method_not_allowed' });

  const token = process.env.INSTAGRAM_ACCESS_TOKEN;
  if (!token) return response.status(503).json({ error: 'instagram_not_configured' });

  try {
    const fields = 'id,caption,media_type,media_url,permalink,thumbnail_url,timestamp';
    const url = new URL('https://graph.instagram.com/me/media');
    url.searchParams.set('fields', fields);
    url.searchParams.set('limit', '12');
    url.searchParams.set('access_token', token);

    const metaResponse = await fetch(url, { headers: { Accept: 'application/json' } });
    const payload = await metaResponse.json();
    if (!metaResponse.ok) {
      console.error('Instagram API error', payload?.error?.code, payload?.error?.type);
      return response.status(502).json({ error: 'instagram_unavailable' });
    }

    const posts = (payload.data || []).map((post) => ({
      id: post.id,
      caption: (post.caption || '').slice(0, 180),
      mediaType: post.media_type,
      image: post.media_type === 'VIDEO' ? post.thumbnail_url : post.media_url,
      permalink: post.permalink,
      timestamp: post.timestamp
    })).filter((post) => post.image && post.permalink).slice(0, 10);

    return response.status(200).json({ profile: '@copyeprint', posts });
  } catch (error) {
    console.error('Instagram feed failed', error?.message);
    return response.status(502).json({ error: 'instagram_unavailable' });
  }
}
