import 'package:flutter/foundation.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import 'theme_palette.dart';

const cardRadius = 16.0;

/// 网站同款状态胶囊徽章：全圆、同色 1px 描边、同色浅底。
class Capsule extends StatelessWidget {
  const Capsule(this.text, {super.key, this.color, this.soft});

  final String text;
  final Color? color;
  final Color? soft;

  @override
  Widget build(BuildContext context) {
    final c = color ?? SemColors.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: soft ?? c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.withValues(alpha: 0.55)),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: c),
      ),
    );
  }
}

/// 液态玻璃卡片（复刻 anticlass .panel）：半透明玻璃面 + 顶部高光渐变 +
/// 玻璃描边 + 柔和外投影。全站卡片统一入口。
class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.padding, this.onTap, this.radius});

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final r = radius ?? cardRadius;
    final base = SemColors.card;
    // 顶边白色高光渐变（CSS: linear-gradient 白 10% → 透明 50%），合成进同一渐变
    final top = Color.alphaBlend(Colors.white.withValues(alpha: 0.10), base);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DecoratedBox(
        // 阴影画在 Material/Ink 之外：InkFeature 会被 Material 画布裁剪，
        // 半透明玻璃面下透出方形阴影角
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(r),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [top, base],
            stops: const [0, 0.5],
          ),
          border: Border.all(color: SemColors.border),
          boxShadow: [
            BoxShadow(
                color: SemColors.shadow, offset: const Offset(0, 8), blurRadius: 24),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(r),
            onTap: onTap,
            child: Padding(
              padding: padding ?? const EdgeInsets.all(16),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// 液态玻璃滑块 Tab（复刻 anticlass .glass-tabs + .slide-thumb-goo）：
/// 玻璃轨道 + 等宽分栏。thumb 可直接拖拽，松手携带释放速度以弹簧动画
/// 甩到目标段（动量）；点击同样以弹簧滑过去。
/// 「外观」滑块（[GlassTabs]，三段：跟随系统 / 浅色 / 深色）的连续位置 → 当前该暗到什么程度：
/// 浅色档 = 0、深色档 = 1；「跟随系统」那一端按系统的实际深浅，中间段线性插值。
/// 拖到 1.5 就是浅色与深色各一半——整站色板按这个值做 [GlassPalette.lerp] 渐变。
/// 静止时它正好等于该档对应的值（0 / 1 / 系统的深浅），所以松手不会跳色。
double appearanceDarkness(double pos, {required bool systemDark}) {
  if (pos >= 1) return (pos - 1).clamp(0.0, 1.0);
  final base = systemDark ? 1.0 : 0.0;
  return base * (1 - pos).clamp(0.0, 1.0);
}

class GlassTabs extends StatefulWidget {
  const GlassTabs({
    super.key,
    required this.labels,
    required this.index,
    required this.onChanged,
    this.height = 34,
    this.fontSize = 12.5,
    this.position,
    this.dragPosition,
  });

  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;
  final double height;
  final double fontSize;

  /// 把「当前连续位置」写出来（每帧都写，单位 = 段，1.5 = 第 2 段与第 3 段中间）：
  /// 调用方据此算实时配色（「外观」滑块）、或让下方内容跟着一起滑动（连接设置）。弹簧仍藏在控件里。
  final ValueNotifier<double>? position;

  /// 页面区域（不是滑块本身）横滑时，调用方通过它驱动同一个位置：
  /// 非 null（拖动中）滑块跟手、不跑自己的弹簧；置回 null（松手）时从当前位置弹到落点。
  final ValueListenable<double?>? dragPosition;

  @override
  State<GlassTabs> createState() => _GlassTabsState();
}

class _GlassTabsState extends State<GlassTabs> with SingleTickerProviderStateMixin {
  // unbounded：set value 不被默认 [0,1] 钳制，拖拽边界由自身 clamp 管理
  late final AnimationController _ctrl = AnimationController.unbounded(
      vsync: this, duration: const Duration(milliseconds: 600))
    ..value = widget.index.toDouble();
  int _target = -1;

  // 欠阻尼弹簧：轻微过冲的回弹手感（thumbGoo 手感）
  static final _spring = SpringDescription.withDampingRatio(mass: 1, stiffness: 260, ratio: 0.72);

  void _springTo(double target, [double velocity = 0]) {
    _target = target.round();
    _ctrl.animateWith(SpringSimulation(_spring, _ctrl.value, target, velocity));
  }

  void _publish() => widget.position?.value = _ctrl.value;

  /// 调用方在页面区域拖动：非 null → 滑块跟手；置回 null（松手）→ 从当前位置弹到落点。
  void _onExternalDrag() {
    final v = widget.dragPosition!.value;
    if (v == null) {
      _springTo(widget.index.toDouble());
    } else {
      _ctrl.value = v.clamp(0.0, (widget.labels.length - 1).toDouble());
    }
  }

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_publish); // 所有位移都经过 _ctrl：弹簧、跟手、外部驱动
    widget.dragPosition?.addListener(_onExternalDrag);
    _publish();
  }

  @override
  void didUpdateWidget(covariant GlassTabs old) {
    super.didUpdateWidget(old);
    // 页面区域拖动中位置由调用方给，别在这儿又弹一次（会跟手指打架）
    if (widget.dragPosition?.value != null) return;
    // 外部状态变化驱动滑动；自身触发的回调已在动量动画中，不重启
    if (old.index != widget.index && widget.index != _target) {
      _springTo(widget.index.toDouble());
    }
  }

  @override
  void dispose() {
    widget.dragPosition?.removeListener(_onExternalDrag);
    _ctrl.removeListener(_publish);
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.labels.length;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: SemColors.cardElevated,
        borderRadius: BorderRadius.circular(widget.height / 2 + 3),
        border: Border.all(color: SemColors.border),
      ),
      child: LayoutBuilder(
        builder: (context, cons) {
          final segW = cons.maxWidth / n;
          final drag = widget.dragPosition;
          return SizedBox(
            height: widget.height,
            child: AnimatedBuilder(
              animation: drag == null ? _ctrl : Listenable.merge([_ctrl, drag]),
              builder: (context, _) {
                // 页面区域拖动中滑块跟手（调用方给的位置）；否则用自身的弹簧位置
                final pos = (drag?.value ?? _ctrl.value).clamp(0.0, (n - 1).toDouble());
                final visual = pos.round().clamp(0, n - 1);
                return Stack(
                  children: [
                    Positioned(
                      left: pos * segW,
                      width: segW,
                      top: 0,
                      height: widget.height,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(widget.height / 2),
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Color.alphaBlend(
                                  Colors.white.withValues(alpha: 0.25), SemColors.thumb),
                              SemColors.thumb,
                            ],
                          ),
                          border: Border.all(color: SemColors.borderStrong),
                          boxShadow: [
                            BoxShadow(
                                color: SemColors.shadow, offset: const Offset(0, 2), blurRadius: 8),
                          ],
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        for (var i = 0; i < n; i++)
                          Expanded(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () {
                                if (i != widget.index) {
                                  _springTo(i.toDouble());
                                  widget.onChanged(i);
                                }
                              },
                              onHorizontalDragStart: (_) => _ctrl.stop(),
                              onHorizontalDragUpdate: (d) =>
                                  _ctrl.value = (_ctrl.value + d.primaryDelta! / segW)
                                      .clamp(0.0, (n - 1).toDouble()),
                              onHorizontalDragEnd: (d) {
                                // 段/秒；速度估计可能爆炸，先饱和
                                final v =
                                    (d.velocity.pixelsPerSecond.dx / segW).clamp(-8.0, 8.0);
                                // 慢速拖拽就近落段；快速甩动（flick）借动量多滑 1 段
                                var target = _ctrl.value.round().clamp(0, n - 1);
                                final next = target + (v > 0 ? 1 : -1);
                                if (v.abs() >= 5.0 && next >= 0 && next <= n - 1) {
                                  target = next;
                                }
                                _springTo(target.toDouble(), v);
                                if (target != widget.index) widget.onChanged(target);
                              },
                              child: Center(
                                child: Text(
                                  widget.labels[i],
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: widget.fontSize,
                                    fontWeight: i == visual ? FontWeight.w600 : FontWeight.w500,
                                    color:
                                        i == visual ? SemColors.textPrimary : SemColors.textMuted,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }
}

/// anticlass 风格输入框：标签在玻璃面外（上方小字），输入面为独立玻璃块，
/// 避免 M3 浮动标签压在边框缺口上的突兀感。
class GlassField extends StatelessWidget {
  const GlassField({
    super.key,
    required this.label,
    this.controller,
    this.focusNode,
    this.obscureText = false,
    this.prefixIcon,
    this.suffixIcon,
    this.hintText,
    this.keyboardType,
    this.enabled = true,
    this.autofocus = false,
    this.maxLines = 1,
    this.textInputAction,
    this.validator,
    this.onSubmitted,
    this.autofillHints,
    this.inputFormatters,
    this.helperText,
    this.helperMaxLines,
  });

  final String label;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final bool obscureText;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final String? hintText;
  final TextInputType? keyboardType;
  final bool enabled;
  final bool autofocus;
  final int? maxLines;
  final TextInputAction? textInputAction;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onSubmitted;
  final Iterable<String>? autofillHints;
  final List<TextInputFormatter>? inputFormatters;
  final String? helperText;
  final int? helperMaxLines;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500)
                .copyWith(color: SemColors.textSecondary)),
        const SizedBox(height: 5),
        TextFormField(
          controller: controller,
          focusNode: focusNode,
          obscureText: obscureText,
          keyboardType: keyboardType,
          enabled: enabled,
          autofocus: autofocus,
          maxLines: maxLines,
          textInputAction: textInputAction,
          validator: validator,
          autofillHints: autofillHints,
          inputFormatters: inputFormatters,
          onFieldSubmitted: onSubmitted,
          decoration: InputDecoration(
            hintText: hintText,
            prefixIcon: prefixIcon,
            suffixIcon: suffixIcon,
            helperText: helperText,
            helperMaxLines: helperMaxLines,
            errorMaxLines: 2,
            isDense: true,
          ),
        ),
      ],
    );
  }
}

/// anticlass 风格下拉选择：标签在面外，同 [GlassField]。
class GlassDropdown<T> extends StatelessWidget {
  const GlassDropdown({
    super.key,
    required this.label,
    required this.items,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final List<DropdownMenuItem<T>> items;
  final T? value;
  final ValueChanged<T?>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500)
                .copyWith(color: SemColors.textSecondary)),
        const SizedBox(height: 5),
        DropdownButtonFormField<T>(
          initialValue: value,
          items: items,
          onChanged: onChanged,
          // 展开占满整行：否则长选项（如「DeepSeek · deepseek.com（官方）」）会横向溢出
          isExpanded: true,
          decoration: const InputDecoration(isDense: true),
        ),
      ],
    );
  }
}

/// 与 [GlassField] 同款的「点开选择」字段：外观就是输入框，但点它弹出选择器而不是下拉。
/// 长列表（上百个模型）用弹窗 + 筛选才好找，又不想和输入框长得不一样，所以做成一族。
class GlassPicker extends StatelessWidget {
  const GlassPicker({
    super.key,
    required this.label,
    required this.value,
    required this.onTap,
    this.hint,
    this.prefixIcon,
    this.helperText,
    this.enabled = true,
  });

  final String label;

  /// 当前值（空串时显示 [hint]）。
  final String value;
  final String? hint;
  final VoidCallback onTap;
  final Widget? prefixIcon;
  final String? helperText;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final empty = value.trim().isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500)
                .copyWith(color: SemColors.textSecondary)),
        const SizedBox(height: 5),
        Opacity(
          opacity: enabled ? 1 : 0.55,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: enabled ? onTap : null,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
                decoration: BoxDecoration(
                  color: SemColors.inputFill,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: SemColors.borderStrong),
                ),
                child: Row(
                  children: [
                    if (prefixIcon != null) ...[
                      IconTheme.merge(
                        data: IconThemeData(color: SemColors.textSecondary, size: 20),
                        child: prefixIcon!,
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: Text(
                        empty ? (hint ?? '未选择') : value,
                        style: TextStyle(
                          fontSize: 14,
                          color: empty ? SemColors.textMuted : SemColors.textPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(Icons.expand_more_rounded,
                        size: 20, color: SemColors.textSecondary),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (helperText != null) ...[
          const SizedBox(height: 4),
          Text(helperText!,
              style: TextStyle(fontSize: 11, color: SemColors.textMuted, height: 1.4)),
        ],
      ],
    );
  }
}

/// 提供商品牌 logo：simple-icons 的 CC0 单色 SVG，按当前主题着色（镂空线稿观感）。
/// [asset] 为空（simple-icons 未收录，如 OpenAI / 智谱）时回退成字母徽章——
/// 比随便挑个通用图标更好认。
class BrandLogo extends StatelessWidget {
  const BrandLogo({
    super.key,
    required this.asset,
    required this.initial,
    this.size = 20,
  });

  final String asset;
  final String initial;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (asset.isEmpty) {
      return Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: SemColors.neutralSoft,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: SemColors.border),
        ),
        child: Text(
          _badgeText(initial),
          style: TextStyle(
              fontSize: size * 0.46,
              fontWeight: FontWeight.w700,
              height: 1,
              letterSpacing: -0.2,
              color: SemColors.textSecondary),
        ),
      );
    }
    return SvgPicture.asset(
      asset,
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(SemColors.textPrimary, BlendMode.srcIn),
    );
  }

  /// 徽章文字：取名称里的拉丁字母/数字前两位（GLM→GL、GPT→GP），否则用首字。
  static String _badgeText(String label) {
    final alnum = RegExp(r'[A-Za-z0-9]').allMatches(label).map((m) => m.group(0)!).join();
    if (alnum.isNotEmpty) {
      final n = alnum.length >= 2 ? 2 : 1;
      return alnum.substring(0, n).toUpperCase();
    }
    final t = label.trim();
    return t.isEmpty ? '?' : t.characters.first.toUpperCase();
  }
}

/// 页面底部的备注区（细字、次要色）：从组件边上挪下来的解释文案归这儿，
/// 组件本身只留标题与状态；更次要的介绍放进「插件管理」的对应插件下方。
class PageNotes extends StatelessWidget {
  const PageNotes({super.key, required this.lines});

  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 4, 6, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(line,
                  style: TextStyle(
                      fontSize: 11, color: SemColors.textMuted, height: 1.6)),
            ),
        ],
      ),
    );
  }
}

/// 30px/600 大数字统计（网站 .cs-stat）。
class BigStat extends StatelessWidget {
  const BigStat({super.key, required this.label, required this.value, this.suffix, this.color});

  final String label;
  final String value;
  final String? suffix;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: SemColors.textMuted)),
        const SizedBox(height: 2),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(value,
                style: TextStyle(
                    fontSize: 30, fontWeight: FontWeight.w600, height: 1.1,
                    color: color ?? SemColors.textPrimary)),
            if (suffix != null) ...[
              const SizedBox(width: 4),
              Text(suffix!,
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700,
                      color: SemColors.textSecondary)),
            ],
          ],
        ),
      ],
    );
  }
}
