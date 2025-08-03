/** @type {import('next').NextConfig} */
const nextConfig = {
  // Only use output: 'export' for production builds, not development
  ...(process.env.NODE_ENV === 'production' && { output: 'export' }),
  eslint: {
    ignoreDuringBuilds: true,
  },
  images: { 
    unoptimized: true 
  },
  // Ensure proper dev server configuration
  experimental: {
    // Disable features that might conflict with development
    serverComponentsExternalPackages: [],
  },
}

module.exports = nextConfig