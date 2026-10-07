interface ImportMetaEnv {
  readonly VITE_PROTECTED_DASH?: string;
  readonly VITE_PROTECTED_HLS?: string;
  readonly VITE_CLEAR_HLS?: string;
  readonly VITE_LICENSE_URL?: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}
