#version 460 core
#include <flutter/runtime_effect.glsl>

// 顶栏「渐进模糊」：**一维**高斯（可分离），横向一趟 + 纵向一趟分别挂在两个
// BackdropFilter 上（第二个能采到第一个的输出，等价于一次 2D 高斯）。
//
// 为什么不用单趟 2D：方阵采样在 σ 大时步长必须拉很大（欠采样），会出方格纹路；
// 为什么不用 ImageFilter.compose：本项目的 Flutter 版本里，compose 组合两个 shader
// filter 会静默失效（渲染成透明）。
//
// 采样密度参考成熟实现（liquid_glass_widgets）：每轴 kHalf=24 tap，
// stride = max(1, 3σ/24) 保证覆盖 ±3σ，配合双线性过滤足够平滑。

// 引擎注入：backdrop 纹理的像素尺寸（第一个 uniform 必须是 vec2，且必须有 sampler）
uniform vec2 u_size;
uniform sampler2D u_texture_input;

uniform vec2 u_region_origin; // 顶栏区域左上角（物理像素）
uniform vec2 u_region_size; // 顶栏区域尺寸（物理像素）
uniform float u_sigma_max; // 最大模糊强度（物理像素）
uniform float u_fade_start; // 渐变起点占区域高度的比例（0~1）
uniform float u_curve; // 渐变曲线指数
uniform float u_axis; // 0 = 横向这一趟，1 = 纵向这一趟

out vec4 frag_color;

const int kHalf = 24; // 单侧采样数：共 49 tap / 趟

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

  vec4 centerTap = texture(u_texture_input, uv);

  if (sigma < 0.5) {
    frag_color = centerTap;
  } else {
    // 本趟只沿一个轴采样，步长按 σ 自适应，保证覆盖 ±3σ
    vec2 axis = (u_axis < 0.5)
        ? vec2(1.0 / u_size.x, 0.0)
        : vec2(0.0, 1.0 / u_size.y);
    float stride = max(1.0, 3.0 * sigma / float(kHalf));

    // 递推权重：w(i) = exp(-(i·stride)²/(2σ²))，避免每个 tap 调一次 exp()
    float inv2s2 = 1.0 / (2.0 * sigma * sigma);
    float g1 = exp(-stride * stride * inv2s2);
    float g2 = g1 * g1;

    vec4 acc = centerTap;
    float wsum = 1.0;
    float w = 1.0;
    for (int i = 1; i <= kHalf; i++) {
      float d = float(i) * stride;
      w *= g1;
      g1 *= g2;
      vec2 off = axis * d;
      vec2 sp = uv + off;
      vec2 sm = uv - off;
      // 越界采样丢弃（clamp 会把边缘像素拉出来抹成条）
      float ip = step(0.0, sp.x) * step(sp.x, 1.0) *
          step(0.0, sp.y) * step(sp.y, 1.0);
      float im = step(0.0, sm.x) * step(sm.x, 1.0) *
          step(0.0, sm.y) * step(sm.y, 1.0);
      acc += texture(u_texture_input, clamp(sp, 0.0, 1.0)) * (w * ip);
      acc += texture(u_texture_input, clamp(sm, 0.0, 1.0)) * (w * im);
      wsum += w * ip + w * im;
    }
    frag_color = acc / wsum;
  }
}
