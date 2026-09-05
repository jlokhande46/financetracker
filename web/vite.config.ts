import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import { VitePWA } from "vite-plugin-pwa";

export default defineConfig({
  plugins: [
    react(),
    VitePWA({
      registerType: "autoUpdate",
      includeAssets: ["icons/*.png"],
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
        start_url: "/",
        scope: "/",
        icons: [
          { src: "/icons/icon-192.png", sizes: "192x192", type: "image/png" },
          { src: "/icons/icon-512.png", sizes: "512x512", type: "image/png" },
          { src: "/icons/icon-512.png", sizes: "512x512", type: "image/png", purpose: "maskable" },
        ],
      },
      workbox: {
        globPatterns: ["**/*.{js,css,html,png,svg,woff2}"],
      },
    }),
  ],
  test: {
    globals: true,
    environment: "node",
  },
} as never);
