import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import { VitePWA } from "vite-plugin-pwa";

/**
 * Where the app will be served from.
 *
 * Root by default (Cloudflare Pages, Netlify, a custom domain). GitHub Pages
 * project sites live at `/<repo>/` instead, and every absolute path in the
 * build — assets, the manifest, the service worker's scope — has to agree with
 * that or the app 404s on load. Set BASE_PATH=/financetracker/ for those.
 */
const base = process.env.BASE_PATH ?? "/";
const at = (path: string) => `${base}${path.replace(/^\//, "")}`;

export default defineConfig({
  base,
  plugins: [
    react(),
    VitePWA({
      registerType: "autoUpdate",
      includeAssets: ["icons/*.png"],
      // A hand-written worker, because a generated one has no `push` handler —
      // and Web Push is the only way an iOS PWA can deliver a reminder.
      strategies: "injectManifest",
      srcDir: "src",
      filename: "sw.ts",
      injectManifest: {
        globPatterns: ["**/*.{js,css,html,png,svg,woff2}"],
      },
      manifest: {
        name: "FinanceTracker",
        short_name: "Finance",
        description: "Personal finance tracking for the Indian market.",
        // `standalone` is what makes iOS treat this as an installed app —
        // which is also what lifts Safari's 7-day script-storage cap and
        // unlocks Web Push on iOS 16.4+.
        display: "standalone",
        orientation: "portrait",
        background_color: "#0A0A0F",
        theme_color: "#7B6EF6",
        start_url: base,
        // Scope has to cover the served path, or iOS refuses to install the
        // PWA — and without an install there's no Web Push on iOS at all.
        scope: base,
        icons: [
          { src: at("icons/icon-192.png"), sizes: "192x192", type: "image/png" },
          { src: at("icons/icon-512.png"), sizes: "512x512", type: "image/png" },
          { src: at("icons/icon-512.png"), sizes: "512x512", type: "image/png", purpose: "maskable" },
        ],
      },
    }),
  ],
  test: {
    globals: true,
    environment: "node",
  },
} as never);
