/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE_API_URL?: string
  readonly VITE_AUTH_ENABLED?: string
  readonly VITE_JWT_USERNAME?: string
  readonly VITE_JWT_PASSWORD?: string
  readonly VITE_AUTH_METHOD?: 'none' | 'jwt' | 'entraid'
}

interface ImportMeta {
  readonly env: ImportMetaEnv
}
