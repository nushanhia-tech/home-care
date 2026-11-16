import type { NextConfig } from 'next';
const nextConfig: NextConfig = {
  poweredByHeader: false,
  outputFileTracingIncludes: {'/api/[...path]':['./assets/fonts/*.ttf']},
  async headers() {
    return [{source:'/:path*',headers:[
      {key:'X-Content-Type-Options',value:'nosniff'},
      {key:'Referrer-Policy',value:'strict-origin-when-cross-origin'},
      {key:'Permissions-Policy',value:'camera=(), microphone=(self), geolocation=(self), speaker-selection=(self)'},
      {key:'X-Frame-Options',value:'DENY'}
    ]}];
  }
};
export default nextConfig;
