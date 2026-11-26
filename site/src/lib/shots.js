// 展示图：每页两套配色（dark / light），由 test/site_shots_test.dart 从当前源码生成，
// 再由 tool/site_shots.py 导出成 900 宽 JPEG。站点按访客主题二选一 —— 图永远跟着网站配色。
export function shotSrc(id, theme) {
  const suffix = theme === "light" ? "light" : "dark";
  return "./img/shots/" + id + "-" + suffix + ".jpg";
}
