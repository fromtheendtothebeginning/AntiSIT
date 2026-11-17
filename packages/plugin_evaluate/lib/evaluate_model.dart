import 'dart:convert';

/// 评教页里识别到的一个评分项（页面上的一个「评价指标」）。
///
/// 分值语义有两种：**离散**（单选组 / 下拉，[values] 是页面给的那些分值，如 5/4/3/2/1）
/// 与**连续**（滑块，[min]..[max] 按 [step] 走）。[index] 是页面脚本里的下标——
/// 应用分数时回传它，所以标签取不到也不影响打分。
class EvalItem {
  const EvalItem({
    required this.index,
    required this.label,
    required this.kind,
    required this.value,
    required this.min,
    required this.max,
    this.step = 1,
    this.values = const [],
  });

  final int index;

  /// 指标名（页面上取到的文本；取不到就是空串，界面上退化成「第 N 项」）。
  final String label;

  /// `radio` / `range` / `slider` / `select`：只用于界面说明，不参与逻辑。
  final String kind;

  /// 页面当前分值。
  final double value;
  final double min;
  final double max;
  final double step;

  /// 可选分值（离散项）；空 = 连续滑块。
  final List<double> values;

  bool get discrete => values.length > 1;

  /// 界面标题：没取到指标名时给个序号，别显示空白行。
  String get title => label.trim().isNotEmpty ? label : '第 ${index + 1} 项';

  /// 把 [raw] 收进本项的合法取值：离散项吸附到最近的合法分值，连续项夹进 [min,max]
  /// 并按 [step] 对齐——统一分数是「一项一分值」，页面允许多少就落在最近的那档。
  double snap(double raw) {
    if (!raw.isFinite) return value;
    if (discrete) {
      var best = values.first;
      var bestGap = (best - raw).abs();
      for (final v in values.skip(1)) {
        final gap = (v - raw).abs();
        if (gap < bestGap) {
          best = v;
          bestGap = gap;
        }
      }
      return best;
    }
    var v = raw < min ? min : (raw > max ? max : raw);
    if (step > 0) {
      final steps = ((v - min) / step).round();
      v = min + steps * step;
    }
    return v.clamp(min, max);
  }

  EvalItem copyWith({double? value}) => EvalItem(
        index: index,
        label: label,
        kind: kind,
        value: value ?? this.value,
        min: min,
        max: max,
        step: step,
        values: values,
      );

  /// 从页面脚本发来的一项解析；结构不对（没有分值范围）就返回 null 跳过它。
  static EvalItem? tryParse(Object? raw) {
    if (raw is! Map) return null;
    double? asDouble(Object? v) {
      if (v is num) return v.toDouble();
      return double.tryParse('$v'.trim());
    }

    final min = asDouble(raw['min']);
    final max = asDouble(raw['max']);
    if (min == null || max == null || max <= min) return null;
    final kind = '${raw['kind'] ?? 'radio'}';
    final value = (asDouble(raw['value']) ?? min).clamp(min, max);
    final stepRaw = asDouble(raw['step']);
    final values = <double>[
      for (final v in (raw['values'] is List ? raw['values'] as List : const <Object?>[]))
        if (asDouble(v) case final d?) d,
    ]..sort();
    final index = raw['index'] is num
        ? (raw['index'] as num).toInt()
        : int.tryParse('${raw['index']}') ?? -1;
    if (index < 0) return null;
    return EvalItem(
      index: index,
      label: '${raw['label'] ?? ''}'.trim(),
      kind: kind,
      value: value,
      min: min,
      max: max,
      step: (stepRaw == null || stepRaw <= 0) ? 1 : stepRaw,
      values: values,
    );
  }
}

/// 一次扫描的结果：识别到的评分项，以及「一个都没认出来」时的说明。
class EvalScan {
  const EvalScan({required this.items, this.hint = '', this.login = false});

  final List<EvalItem> items;

  /// 没识别到时的提示（含页面上的候选控件计数，方便判断是改版还是没登录）。
  final String hint;

  /// 当前页面看着像教务登录页（需要先登录）。
  final bool login;

  bool get isEmpty => items.isEmpty;
}

/// 解析网页脚本发来的消息；不是「扫描结果」类消息就返回 null（应用回执见
/// [parseEvalApplied]）。
EvalScan? parseEvalMessage(String raw) {
  final Object? j = _decode(raw);
  if (j is! Map) return null;
  final type = '${j['t'] ?? ''}';
  if (type == 'none') {
    return EvalScan(
      items: const [],
      hint: _noneHint(j['counts'], j['samples']),
      login: j['login'] == true,
    );
  }
  if (type != 'items') return null;
  final list = j['items'];
  if (list is! List) return null;
  final items = <EvalItem>[
    for (final it in list)
      if (EvalItem.tryParse(it) case final item?) item,
  ];
  if (items.isEmpty) {
    return EvalScan(items: const [], hint: '页面里没有可用的评分项', login: j['login'] == true);
  }
  return EvalScan(items: items, login: j['login'] == true);
}

/// 「已应用」回执：页面吸附之后每一项的真实分值（项下标 → 分值）。
/// 统一分数打到单选组上时，页面可能就近取档，所以要以回执为准刷新界面。
Map<int, double> parseEvalApplied(String raw) {
  final Object? j = _decode(raw);
  if (j is! Map || '${j['t'] ?? ''}' != 'applied') return const {};
  final values = j['values'];
  if (values is! Map) return const {};
  final out = <int, double>{};
  values.forEach((k, v) {
    final index = int.tryParse('$k');
    final d = v is num ? v.toDouble() : double.tryParse('$v');
    if (index != null && d != null) out[index] = d;
  });
  return out;
}

Object? _decode(String raw) {
  try {
    return jsonDecode(raw);
  } catch (_) {
    return null;
  }
}

String _noneHint(Object? counts, Object? samples) {
  final c = counts is Map ? counts : const {};
  int n(String key) {
    final v = c[key];
    if (v is num) return v.toInt();
    return int.tryParse('$v') ?? 0;
  }

  final parts = <String>[
    if (n('text') > 0) '评分输入框 ${n('text')} 个',
    if (n('radio') > 0) '单选组 ${n('radio')} 个',
    if (n('range') > 0) '滑块 ${n('range')} 个',
    if (n('slider') > 0) '页面滑块 ${n('slider')} 个',
    if (n('select') > 0) '下拉 ${n('select')} 个',
  ];
  final seen = parts.isEmpty ? '一个候选控件都没找到' : '只找到 ${parts.join(' / ')}';
  // 采样：页面上实际有哪些输入控件（改版时一眼看出它变成了什么形态）
  final shapes = <String>[];
  if (samples is List) {
    for (final s in samples.take(3)) {
      if (s is! Map) continue;
      final tag = '${s['tag'] ?? ''}'.trim();
      final type = '${s['type'] ?? ''}'.trim();
      final hint = '${s['placeholder'] ?? ''}'.trim();
      final label = [tag, if (type.isNotEmpty) type].join('/');
      if (label.isEmpty) continue;
      shapes.add(hint.isEmpty ? label : '$label（$hint）');
    }
  }
  final detail = shapes.isEmpty ? '' : '；页面输入控件：${shapes.join('、')}';
  return '没识别到评分项（$seen，评教页可能改版了$detail）';
}

/// 评教「评价详情」页在教务域名下的相对路径（正方 N401605）。
const String kEvaluatePath =
    '/xspjgl/xspj_cxXspjIndex.html?doType=details&gnmkdm=N401605&layout=default';

/// 评教页地址：按学校档案里的教务域名拼，换学校自动换域名（默认就是 SIT 教务）。
String evalUrlFor(String jwxtBase) {
  final base = jwxtBase.trim().replaceAll(RegExp(r'/+$'), '');
  if (base.isEmpty) return '';
  return '$base/jwglxt$kEvaluatePath';
}

/// 教务登录页（评教页被踢回登录时，从这里登进去再回来）。
String evalLoginUrlFor(String jwxtBase) {
  final base = jwxtBase.trim().replaceAll(RegExp(r'/+$'), '');
  if (base.isEmpty) return '';
  return '$base/jwglxt/xtgl/login_slogin.html';
}
