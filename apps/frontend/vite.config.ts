import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

export default defineConfig({
  plugins: [react()],
  server: {
    // `npm run dev` talks to the API from docker-compose.
    proxy: { "/api": "http://localhost:8000" },
  },
});
