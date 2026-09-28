const APEX = 'sushantnagil.com';

export default {
  fetch(request) {
    const url = new URL(request.url);
    url.protocol = 'https:';
    url.hostname = APEX;
    url.port = '';
    return new Response(null, {
      status: 301,
      headers: {
        Location: url.toString(),
        'Strict-Transport-Security': 'max-age=31536000; includeSubDomains',
        'Cache-Control': 'public, max-age=86400',
      },
    });
  },
};
