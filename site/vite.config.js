import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// 站点挂在 https://anticraft.top/antiSIT/ 下：相对 base 保证打包产物路径可整目录搬迁
export default defineConfig({
  base: "./",
  plugins: [react()],
  build: { outDir: "dist", assetsDir: "assets" }
});
