export default async function handler(req: Request) {
    if (req.method !== 'POST') {
        return new Response('Method not allowed', { status: 405 });
    }

    try {
        const rawBody = await req.text();
        const tokenResponse = await fetch('https://login.live.com/oauth20_token.srf', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/x-www-form-urlencoded',
            },
            body: rawBody,
        });

        const data = await tokenResponse.json();

        if (tokenResponse.ok && (typeof data.access_token !== 'string' || data.access_token.trim().length < 20)) {
            return new Response(JSON.stringify({ error: 'OAuth provider returned an invalid access token' }), {
                status: 502,
                headers: { 'Content-Type': 'application/json' },
            });
        }

        return new Response(JSON.stringify(data), {
            status: tokenResponse.status,
            headers: {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Methods': 'POST, OPTIONS',
                'Access-Control-Allow-Headers': 'Content-Type'
            }
        });
    } catch {
        return new Response(JSON.stringify({ error: 'Proxy failed to reach Live OAuth' }), {
            status: 502,
            headers: { 'Content-Type': 'application/json' }
        });
    }
}
