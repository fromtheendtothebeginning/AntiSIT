import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

import 'evaluate_model.dart';

/// 评分助手面板此刻的样子：识别到哪些项、是不是在等页面回执、要不要先登录。
class EvaluatePanelState {
  const EvaluatePanelState({
    required this.items,
    this.hint = '',
    this.login = false,
    this.busy = false,
  });

  final List<EvalItem> items;

  /// 没识别到评分项时的说明（页面上有哪些候选控件，用来区分改版 / 没登录）。
  final String hint;
  final bool login;
  final bool busy;

  EvaluatePanelState copyWith({
    List<EvalItem>? items,
    String? hint,
    bool? login,
    bool? busy,
  }) =>
      EvaluatePanelState(
        items: items ?? this.items,
        hint: hint ?? this.hint,
        login: login ?? this.login,
        busy: busy ?? this.busy,
      );
}

/// 评分助手面板：上面一条**统一分数**滑块（一键同分用），下面按指标逐项一条滑块。
/// 与网页的交互全部走回调——面板自己不碰 WebView，方便单测。
class EvaluatePanel extends StatefulWidget {
  const EvaluatePanel({
    super.key,
    required this.state,
    required this.onApplyAll,
    required this.onApplyOne,
    required this.onRescan,
    required this.onLogin,
  });

  final EvaluatePanelState state;

  /// 一键同分：把这个分数打到当前这一页的所有评分项。
  final ValueChanged<double> onApplyAll;

  /// 逐项调分：只改这一项（松手时触发）。
  final void Function(EvalItem item, double value) onApplyOne;

  /// 重新识别（页面自己改过 DOM / 换过页之后用）。
  final VoidCallback onRescan;

  /// 去教务登录页（面板判断出当前是登录页时）。
  final VoidCallback onLogin;

  @override
  State<EvaluatePanel> createState() => _EvaluatePanelState();
}

class _EvaluatePanelState extends State<EvaluatePanel> {
  /// 统一分数。null = 还没初始化（识别到评分项后默认取全部项的最高分）。
  double? _uniform;

  /// 拖动中的本地值：松手后页面回执会把它换成「页面真正落到的分」，期间先按用户拖的显示。
  final Map<int, double> _pending = {};

  List<EvalItem> get _items => widget.state.items;

  double get _min => _items.fold(_items.first.min, (a, e) => math.min(a, e.min));
  double get _max => _items.fold(_items.first.max, (a, e) => math.max(a, e.max));

  /// 统一滑块的步长取各项里最细的那一档（统一分数落到哪档由页面就近取）。
  double get _step {
    var s = double.infinity;
    for (final e in _items) {
      if (e.step > 0 && e.step < s) s = e.step;
    }
    return (s.isFinite && s > 0) ? s : 1;
  }

  @override
  void initState() {
    super.initState();
    _initUniform();
  }

  @override
  void didUpdateWidget(covariant EvaluatePanel old) {
    super.didUpdateWidget(old);
    if (old.state.items.isEmpty && _items.isNotEmpty) _initUniform();
    // 页面回执到了：把手里的临时值换成页面的真实分值
    if (_pending.isNotEmpty) {
      _pending.removeWhere((index, value) {
        for (final item in _items) {
          if (item.index == index) return (item.value - value).abs() < 0.001;
        }
        return true;
      });
    }
    final u = _uniform;
    if (u != null && _items.isNotEmpty && (u < _min || u > _max)) {
      _uniform = _max;
    }
  }

  void _initUniform() {
    if (_items.isEmpty) {
      _uniform = null;
      return;
    }
    _uniform = _max;
  }

  /// 分值显示：整数步长一律显示整数（容掉浮点误差），其余留一位小数。
  String _fmt(double v) {
    final r = v.roundToDouble();
    return (v - r).abs() < 0.001 ? '${r.round()}' : v.toStringAsFixed(1);
  }

  int _divisionsFor(double min, double max, double step) {
    if (max <= min) return 1;
    final n = step > 0 ? ((max - min) / step).round() : 10;
    return n.clamp(1, 40);
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.busy) const LinearProgressIndicator(minHeight: 2),
        if (state.login) _loginBanner(context),
        if (_items.isEmpty)
          Expanded(child: _emptyBody(context))
        else ...[
          _uniformBlock(context),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 2),
            child: Row(
              children: [
                Text('逐项调分',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: SemColors.textPrimary)),
                const SizedBox(width: 8),
                Text('识别到 ${_items.length} 项',
                    style: TextStyle(fontSize: 12, color: SemColors.textMuted)),
                const Spacer(),
                TextButton.icon(
                  onPressed: state.busy ? null : widget.onRescan,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('重新识别', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
          Expanded(child: _itemList(context)),
        ],
      ],
    );
  }

  Widget _loginBanner(BuildContext context) => Container(
        color: SemColors.warning.withValues(alpha: 0.12),
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Row(
          children: [
            Icon(Icons.lock_outline, size: 16, color: SemColors.warning),
            const SizedBox(width: 8),
            Expanded(
              child: Text('当前是教务登录页：先登录，再回到评教页识别',
                  style: TextStyle(fontSize: 12.5, color: SemColors.textSecondary)),
            ),
            TextButton(onPressed: widget.onLogin, child: const Text('去登录')),
          ],
        ),
      );

  Widget _emptyBody(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Icon(Icons.rule_folder_outlined, size: 38, color: SemColors.textMuted),
            const SizedBox(height: 12),
            Text(
              widget.state.hint.isEmpty ? '没识别到评分项' : widget.state.hint,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, height: 1.7, color: SemColors.textSecondary),
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: widget.state.busy ? null : widget.onRescan,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('重新识别'),
            ),
            const SizedBox(height: 10),
            Text('如果页面上确实有评分项，可能是评教页面结构变了',
                style: TextStyle(fontSize: 11.5, color: SemColors.textMuted)),
          ],
        ),
      );

  /// 统一分数：**拖动即生效**——拖到哪，这一页所有评分项就打到哪（不再需要「一键同分」按钮）。
  /// 显示和下发都用整数分：Slider 的离散换算会带出 55.00000000000001 这类浮点尾巴，
  /// 直接写进页面输入框就成了错数据。
  Widget _uniformBlock(BuildContext context) {
    final raw = (_uniform ?? _max).clamp(_min, _max);
    final v = _snapUniform(raw);
    final divisions = _divisionsFor(_min, _max, _step);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('统一分数',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: SemColors.textPrimary)),
              const Spacer(),
              Text(_fmt(v),
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: SemColors.accent)),
              Text(' 分',
                  style: TextStyle(fontSize: 12, color: SemColors.textMuted)),
            ],
          ),
          Slider(
            value: raw,
            min: _min,
            max: _max,
            divisions: divisions,
            label: _fmt(v),
            onChanged: _changeUniform,
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              '拖到哪就打到哪：当前 ${_fmt(v)} 分 → 这一页全部 ${_items.length} 项',
              style: TextStyle(fontSize: 11.5, color: SemColors.textMuted),
            ),
          ),
        ],
      ),
    );
  }

  /// 拖动统一滑块：每一项先按自己的步长吸附到同一个分数（本地立刻跟手），再一次性下发到页面。
  void _changeUniform(double x) {
    setState(() {
      _uniform = x;
      for (final item in _items) {
        _pending[item.index] = item.snap(x);
      }
    });
    widget.onApplyAll(_snapUniform(x));
  }

  /// 拖动逐项滑块：一拖就更新这一项（不用等松手）。
  void _changeItem(EvalItem item, double x) {
    final v = item.snap(x);
    setState(() => _pending[item.index] = v);
    widget.onApplyOne(item, v);
  }

  /// 统一分数吸附到各项里最细的那档；整数步长（百分制）落成整数。
  double _snapUniform(double raw) {
    var v = raw < _min ? _min : (raw > _max ? _max : raw);
    if (_step > 0) v = _min + ((v - _min) / _step).round() * _step;
    if (_step >= 1 && _step == _step.roundToDouble()) v = v.roundToDouble();
    return v < _min ? _min : (v > _max ? _max : v);
  }

  Widget _itemList(BuildContext context) => ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
        itemCount: _items.length,
        itemBuilder: (context, i) {
          final item = _items[i];
          // 一律按各自步长吸附后再显示/拖动：整数字段不会出现 55.00000000000001
          final value = item.snap((_pending[item.index] ?? item.value));
          final divisions = item.discrete
              ? math.max(1, item.values.length - 1)
              : _divisionsFor(item.min, item.max, item.step);
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, height: 1.35, color: SemColors.textSecondary),
                  ),
                ),
                SizedBox(
                  width: 132,
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 2,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                    ),
                    child: Slider(
                      value: value,
                      min: item.min,
                      max: item.max,
                      divisions: divisions,
                      label: _fmt(value),
                      onChanged: (x) => _changeItem(item, x),
                    ),
                  ),
                ),
                SizedBox(
                  width: 34,
                  child: Text(
                    _fmt(value),
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: SemColors.textPrimary),
                  ),
                ),
              ],
            ),
          );
        },
      );
}
