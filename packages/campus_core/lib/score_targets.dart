import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'json_num.dart';

/// 二课达标线：一级板块目标（德育/劳育…）与二级条目目标（讲座/志愿…）。
class ScoreGroupTarget {
  const ScoreGroupTarget({required this.keywords, this.target, this.noExpand = false});

  /// 板块名包含任一关键词即命中（与网站/旧版规则一致）。
  final List<String> keywords;
  final double? target;

  /// 美育 / 健康教育这类只看总分、不展开明细的板块。
  final bool noExpand;

  bool matches(String name) => keywords.any(name.contains);
}

class ScoreSubTarget {
  const ScoreSubTarget({required this.keywords, this.target});

  final List<String> keywords;
  final double? target;

  bool matches(String name) => keywords.any(name.contains);
}

/// 一个年级（或默认）的完整达标策略。
class ScoreTargetPolicy {
  const ScoreTargetPolicy({
    this.label,
    this.total,
    this.groups = const [],
    this.subs = const [],
  });

  /// 可选展示名（如「2026级」）；配置里的 default 通常留空，避免把某届的规则说成通用规则。
  final String? label;

  /// 实践学分总目标；null = 不比较总分。
  final double? total;

  final List<ScoreGroupTarget> groups;
  final List<ScoreSubTarget> subs;

  bool get isEmpty => total == null && groups.isEmpty && subs.isEmpty;

  ScoreGroupTarget? groupFor(String name) {
    for (final g in groups) {
      if (g.matches(name)) return g;
    }
    return null;
  }

  double? subFor(String name) {
    for (final s in subs) {
      if (s.matches(name)) return s.target;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        if (label != null) 'label': label,
        if (total != null) 'total': total,
        'groups': [
          for (final g in groups)
            {
              'keywords': g.keywords,
              if (g.target != null) 'target': g.target,
              if (g.noExpand) 'noExpand': true,
            }
        ],
        'subs': [
          for (final s in subs)
            {
              'keywords': s.keywords,
              if (s.target != null) 'target': s.target,
            }
        ],
      };
}

/// 达标线配置：`default` 是兜底策略，`cohorts` 按入学年（nj）覆盖。
///
/// App 内置一套**默认规则**（与现行达标线一致，不绑定某一届）；远端
/// `score-targets.json` 和用户在本机三级页面的自定义优先。规则调整不需要改代码。
class ScoreTargets {  const ScoreTargets({
    this.defaultPolicy,
    this.cohorts = const {},
    this.local = const {},
  });

  final ScoreTargetPolicy? defaultPolicy;
  final Map<String, ScoreTargetPolicy> cohorts;

  /// 本机自定义：键为入学年，`default` 表示未填年级时的自定义默认值。
  final Map<String, ScoreTargetPolicy> local;

  static const String configUrl = 'https://anticraft.top/apk/score-targets.json';
  static const String _cacheKey = 'score_targets_v1';
  static const String _cacheAtKey = 'score_targets_v1_at';
  static const String _localKey = 'score_targets_local_v1';
  static const Duration _cacheTtl = Duration(hours: 24);
  static const Duration _timeout = Duration(seconds: 3);

  /// 取某届的策略：本机该届自定义 → 远端该届 → 远端默认 → 内置默认规则。
  /// 本机自定义只作用于保存时的年级；未填年级时用本机 `default`。
  ScoreTargetPolicy forCohort(String? nj) {
    final key = (nj ?? '').trim();
    if (key.isNotEmpty) {
      final localHit = local[key];
      if (localHit != null) return localHit;
      final hit = cohorts[key];
      if (hit != null) return hit;
    } else {
      final localDefault = local['default'];
      if (localDefault != null) return localDefault;
    }
    return defaultPolicy ?? _builtInDefault;
  }

  /// 该届是否有本机自定义（设置页用来显示「已自定义」/「恢复默认」）。
  ScoreTargetPolicy? localOverrideFor(String? nj) {
    final key = (nj ?? '').trim();
    return key.isNotEmpty ? local[key] : local['default'];
  }

  /// 保存本机自定义；[policy] 为 null 表示删掉该届的自定义。
  static Future<void> saveLocalOverride(String? nj, ScoreTargetPolicy? policy) async {
    final sp = await SharedPreferences.getInstance();
    final map = <String, dynamic>{};
    final raw = sp.getString(_localKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final j = jsonDecode(raw);
        if (j is Map) map.addAll(j.cast<String, dynamic>());
      } catch (_) {}
    }
    final key = (nj ?? '').trim().isEmpty ? 'default' : (nj ?? '').trim();
    if (policy == null) {
      map.remove(key);
    } else {
      map[key] = policy.toJson();
    }
    if (map.isEmpty) {
      await sp.remove(_localKey);
    } else {
      await sp.setString(_localKey, jsonEncode(map));
    }
  }

  /// 解析配置；不是合法对象返回 null（调用方继续用缓存/空策略）。
  static ScoreTargets? parse(String raw) {
    try {
      final j = jsonDecode(raw);
      if (j is! Map) return null;
      final cohorts = <String, ScoreTargetPolicy>{};
      final rawCohorts = j['cohorts'];
      if (rawCohorts is Map) {
        rawCohorts.forEach((k, v) {
          final p = _policyFrom(v);
          if (p != null) cohorts['$k'.trim()] = p;
        });
      }
      return ScoreTargets(
        defaultPolicy: _policyFrom(j['default']),
        cohorts: cohorts,
      );
    } catch (_) {
      return null;
    }
  }

  /// 读本地缓存（24h）→ 拉远端 → 过期/失败时用旧缓存 → 内置默认规则。
  /// 无论走哪条路，都叠加本机自定义（local）：三级设置页保存后立即生效。
  static Future<ScoreTargets> load() async {
    SharedPreferences? sp;
    String? cached;
    var cachedAt = 0;
    try {
      sp = await SharedPreferences.getInstance();
      cached = sp.getString(_cacheKey);
      cachedAt = sp.getInt(_cacheAtKey) ?? 0;
    } catch (_) {}

    final local = _readLocal(sp);
    ScoreTargets withLocal(ScoreTargets base) => ScoreTargets(
          defaultPolicy: base.defaultPolicy,
          cohorts: base.cohorts,
          local: local,
        );

    final now = DateTime.now().millisecondsSinceEpoch;
    if (cached != null && now - cachedAt >= 0 && now - cachedAt < _cacheTtl.inMilliseconds) {
      final parsed = parse(cached);
      if (parsed != null) return withLocal(parsed);
    }

    try {
      final res = await http.get(
        Uri.parse(configUrl),
        headers: const {'Cache-Control': 'no-cache'},
      ).timeout(_timeout);
      if (res.statusCode == 200) {
        final raw = utf8.decode(res.bodyBytes, allowMalformed: true);
        final parsed = parse(raw);
        if (parsed != null) {
          try {
            await sp?.setString(_cacheKey, raw);
            await sp?.setInt(_cacheAtKey, now);
          } catch (_) {}
          return withLocal(parsed);
        }
      }
    } catch (e) {
      debugPrint('[二课达标线] 拉取配置失败：$e');
    }

    if (cached != null) {
      final parsed = parse(cached);
      if (parsed != null) return withLocal(parsed);
    }
    return withLocal(fallback());
  }

  /// 拉不到配置时的兜底：内置默认规则（现行达标线，不绑定年级）。
  static ScoreTargets fallback() =>
      const ScoreTargets(defaultPolicy: _builtInDefault);

  static Map<String, ScoreTargetPolicy> _readLocal(SharedPreferences? sp) {
    final raw = sp?.getString(_localKey);
    if (raw == null || raw.isEmpty) return const {};
    try {
      final j = jsonDecode(raw);
      if (j is! Map) return const {};
      final out = <String, ScoreTargetPolicy>{};
      j.forEach((k, v) {
        final p = _policyFrom(v);
        if (p != null) out['$k'.trim()] = p;
      });
      return out;
    } catch (_) {
      return const {};
    }
  }

  static ScoreTargetPolicy? _policyFrom(Object? v) {
    if (v is! Map) return null;
    return ScoreTargetPolicy(
      label: _label(v['label']),
      total: asDouble(v['total']),
      groups: _groups(v['groups']),
      subs: _subs(v['subs']),
    );
  }

  static String? _label(Object? v) {
    final s = '${v ?? ''}'.trim();
    return s.isEmpty ? null : s;
  }

  static List<String> _keywords(Object? v) {
    if (v is List) {
      return [for (final e in v) if ('$e'.trim().isNotEmpty) '$e'.trim()];
    }
    final s = '${v ?? ''}'.trim();
    return s.isEmpty ? const [] : [s];
  }

  static List<ScoreGroupTarget> _groups(Object? v) {
    if (v is! List) return const [];
    final out = <ScoreGroupTarget>[];
    for (final raw in v) {
      if (raw is! Map) continue;
      final kw = _keywords(raw['keywords']);
      if (kw.isEmpty) continue;
      out.add(ScoreGroupTarget(
        keywords: kw,
        target: asDouble(raw['target']),
        noExpand: raw['noExpand'] == true,
      ));
    }
    return out;
  }

  static List<ScoreSubTarget> _subs(Object? v) {
    if (v is! List) return const [];
    final out = <ScoreSubTarget>[];
    for (final raw in v) {
      if (raw is! Map) continue;
      final kw = _keywords(raw['keywords']);
      if (kw.isEmpty) continue;
      out.add(ScoreSubTarget(keywords: kw, target: asDouble(raw['target'])));
    }
    return out;
  }
}

/// 内置默认规则：现行达标线，不绑定某一届；远端配置 / 本机自定义可整体覆盖。
const ScoreTargetPolicy _builtInDefault = ScoreTargetPolicy(
  total: 8,
  groups: [
    ScoreGroupTarget(keywords: ['德育'], target: 3.0),
    ScoreGroupTarget(keywords: ['劳育'], target: 3.0),
    ScoreGroupTarget(keywords: ['美育'], target: 1.0, noExpand: true),
    ScoreGroupTarget(keywords: ['健康'], target: 1.0, noExpand: true),
  ],
  subs: [
    ScoreSubTarget(keywords: ['讲座', '报告', '讲坛', '沙龙', '主题教育', '团日'], target: 1.8),
    ScoreSubTarget(keywords: ['安全教育', '安全'], target: 0.2),
    ScoreSubTarget(keywords: ['志愿', '公益'], target: 1.0),
    ScoreSubTarget(
        keywords: ['三创', '竞赛', '论文', '专利', '技能证书', '社团活动'], target: 1.5),
    ScoreSubTarget(keywords: ['社会实践', '挂职', '学长导航', '境外交流'], target: 1.0),
    ScoreSubTarget(keywords: ['劳动教育', '劳动课堂']),
    ScoreSubTarget(keywords: ['校园文明', '文明寝室']),
  ],
);
