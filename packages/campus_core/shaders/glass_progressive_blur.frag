#version 460 core
#include <flutter/runtime_effect.glsl>

// 顶栏「渐进模糊」：单个 BackdropFilter 只捕获一次 backdrop，本 shader 直接对它做
// 一次 2D 高斯卷积；模糊强度随纵坐标渐变（顶栏顶边最强、底边收敛到 0）。
//
// 为什么不做「两趟可分离」：本项目的 Flutter 版本下 `ImageFilter.compose` 组合两个
// shader filter 会静默失效（渲染成透明），所以这里用一次 2D 采样搞定。
// 为了控制采样数，核按 0.75σ 取 7×7 = 49 个 tap，覆盖 ±2.25σ。

// 引擎注入：backdrop 纹理的像素尺寸（第一个 uniform 必须是 vec2，且必须有 sampler）
uniform vec2 u_size;
uniform sampler2D u_texture_input;

// 顶栏区域（物理像素）：把「渐变」归一化到顶栏这一条，而不是整屏
uniform vec2 u_region_origin;
uniform vec2 u_region_size;

uniform float u_sigma_max; // 最大模糊强度（物理像素）
uniform float u_fade_start; // 渐变起点占区域高度的比例（0~1）
uniform float u_curve; // 渐变曲线指数（越大越「顶强底缓」）

out vec4 frag_color;

const int kTaps = 3; // 单侧 3 → 7×7
const float kStep = 0.75; // 步长 = 0.75σ

void main() {
  vec2 frag = FlutterFragCoord().xy;

  // GLES 后端的 backdrop 捕获是上下颠倒的（Flutter 官方示例同款处理）
  #ifdef IMPELLER_TARGET_OPENGLES
  vec2 fragRegion = vec2(frag.x, u_size.y - frag.y);
  #else
  vec2 fragRegion = frag;
  #endif

  // 归一化到顶栏区域：t=0 是顶栏顶边，t=1 是顶栏底边
  vec2 regionSize = max(u_region_size, vec2(1.0));
  vec2 r = (fragRegion - u_region_origin) / regionSize;
  float t = clamp(r.y, 0.0, 1.0);

  // 顶部一段保持最强，fade_start 之后按曲线衰减到 0（顶栏底边 = 清晰）
  float k = 1.0;
  if (t > u_fade_start) {
    float f = (t - u_fade_start) / max(1.0 - u_fade_start, 1e-4);
    k = pow(max(0.0, 1.0 - f), u_curve);
  }
  float sigma = u_sigma_max * k;

  vec2 uv = frag / u_size;
  #ifdef IMPELLER_TARGET_OPENGLES
  uv.y = 1.0 - uv.y;
  #endif

  vec2 stepUv = (sigma * kStep) / u_size;

  vec4 acc = vec4(0.0);
  float total = 0.0;
  for (int j = -kTaps; j <= kTaps; j++) {
    for (int i = -kTaps; i <= kTaps; i++) {
      float fi = float(i);
      float fj = float(j);
      // 偏移 = (i,j)·0.75σ ⇒ 权重 exp(-(i²+j²)·0.75²/2) = exp(-0.28125·(i²+j²))
      float w = exp(-0.28125 * (fi * fi + fj * fj));
      acc += texture(u_texture_input, uv + stepUv * vec2(fi, fj)) * w;
      total += w;
    }
  }
  frag_color = acc / total;
}
