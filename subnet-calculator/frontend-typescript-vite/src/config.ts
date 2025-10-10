export const API_CONFIG = {
  baseUrl: import.meta.env.VITE_API_URL || 'http://localhost:8090',
  paths: {
    health: '/api/v1/health',
    // Azure Function uses /ipv4/ prefix, Container App uses /address/ and /subnets/
    validate: '/api/v1/ipv4/validate',
    checkPrivate: '/api/v1/ipv4/check-private',
    checkCloudflare: '/api/v1/ipv4/check-cloudflare',
    subnetInfo: '/api/v1/ipv4/subnet-info',
  },
}
