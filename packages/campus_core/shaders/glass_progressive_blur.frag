#version 460 core
#include <flutter/runtime_effect.glsl>

// 顶栏「渐进模糊」：单个 BackdropFilter 只捕获一次 backdrop，本 shader 一次绘制完成
// 2D 高斯卷积，模糊强度随纵坐标渐变（顶栏顶边最强、底边收敛到 0）。
//
// 为什么是单趟：两个 backdrop 捕获（横向 + 纵向两趟）在滚动 / overscroll 时，
// 第二个会采到上一帧或中间态的内容，重影会「挂」在顶栏上；只有一个捕获才彻底没有。
//
// 单趟 2D 怎么避免栅格纹：采样点按 0.6σ 铺成方阵，再按「每像素随机旋转」打散——
// 方阵的有序结构被打碎成高频噪点（被高斯权重一压基本不可见），不会出现规则格子。
//
// 权重用递推（w(n) = exp(-(n·stride)²/(2σ²)) 的等比数列），避免每个 tap 调一次 exp()。

// 引擎注入：backdrop 纹理的像素尺寸（第一个 uniform 必须是 vec2，且必须有 sampler）
uniform vec2 u_size;
uniform sampler2D u_texture_input;

uniform vec2 u_region_origin; // 顶栏区域左上角（物理像素）
uniform vec2 u_region_size; // 顶栏区域尺寸（物理像素）
uniform float u_sigma_max; // 最大模糊强度（物理像素）
uniform float u_fade_start; // 渐变起点占区域高度的比例（0~1）
uniform float u_curve; // 渐变曲线指数

out vec4 frag_color;

// 单侧 5 → 11×11 = 121 个 tap
const int kHalf = 5;

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
  vec2 rr = (fragRegion - u_region_origin) / regionSize;
  float t = clamp(rr.y, 0.0, 1.0);

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

  if (sigma < 0.5) {
    frag_color = texture(u_texture_input, uv);
  } else {
    float stride = max(1.0, 3.0 * sigma / float(kHalf)); // 物理像素
    float inv2s2 = 1.0 / (2.0 * sigma * sigma);
    float g1 = exp(-stride * stride * inv2s2); // w(n+1)/w(n)
    float g2 = g1 * g1;

    // 每像素随机旋转：把方阵采样打散成噪点，避免规则格纹
    float ign = fract(52.9829189 * fract(0.06711056 * frag.x + 0.00583715 * frag.y));
    float rot = ign * 6.2831853;
    float cr = cos(rot);
    float sr = sin(rot);

    vec4 acc = vec4(0.0);
    float wsum = 0.0;

    // 中心 tap
    acc += texture(u_texture_input, uv);
    wsum += 1.0;

    float wy = 1.0;
    float gy = g1;
    float gyStep = g2;
    for (int jn = 1; jn <= kHalf; jn++) {
      wy *= gy;
      gy *= gyStep;
      for (int js = 0; js < 2; js++) {
        float fj = (js == 0) ? float(jn) : -float(jn);
        float wx = 1.0;
        float gx = g1;
        float gxStep = g2;
        // 中间那一列（i = 0）
        {
          vec2 p = vec2(0.0, fj) * stride;
          vec2 pr = vec2(p.x * cr - p.y * sr, p.x * sr + p.y * cr);
          float w = wy;
          acc += texture(u_texture_input, clamp(uv + pr / u_size, 0.0, 1.0)) * w;
          wsum += w;
        }
        for (int ii = 1; ii <= kHalf; ii++) {
          wx *= gx;
          gx *= gxStep;
          for (int isg = 0; isg < 2; isg++) {
            float fi = (isg == 0) ? float(ii) : -float(ii);
            vec2 p = vec2(fi, fj) * stride;
            vec2 pr = vec2(p.x * cr - p.y * sr, p.x * sr + p.y * cr);
            float w = wx * wy;
            acc += texture(u_texture_input, clamp(uv + pr / u_size, 0.0, 1.0)) * w;
            wsum += w;
          }
        }
      }
    }
    frag_color = acc / wsum;
  }
}
