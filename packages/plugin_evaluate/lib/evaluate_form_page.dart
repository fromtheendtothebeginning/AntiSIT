import 'dart:async';

import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

import 'evaluate_api.dart';
import 'evaluate_cache.dart';
import 'evaluate_model.dart';

/// 评分表单列表的内边距：留白必须进列表自己的 padding，内容才能从悬浮顶栏 /
/// 底栏底下穿过去（issue #15）。
EdgeInsets evaluateFormListPadding(
  double topInset, {
  double bottomInset = 0,
}) =>
    EdgeInsets.fromLTRB(12, 8 + topInset, 12, 24 + bottomInset);

/// 单个老师的评分页：一列题 + 一条「统一分数」滑条 + 保存 / 提交。
/// 保存可反复覆盖；提交不可撤销且必须写完复查（服务端对非法请求也会先回「成功」）。
class EvaluateFormPage extends StatefulWidget {
  const EvaluateFormPage({
    super.key,
    required this.api,
    required this.target,
    required this.onChanged,
  });

  final EvaluateApi api;
  final EvalTarget target;

  final Future<void> Function() onChanged;

  @override
  State<EvaluateFormPage> createState() => _EvaluateFormPageState();
}

class _EvaluateFormPageState extends State<EvaluateFormPage> {
  EvalForm? _form;
  bool _loading = true;
  String? _error;
  final String _log = '';

  /// 指标 ID → 分数。
  final Map<String, double> _scores = {};
  final TextEditingController _comment = TextEditingController();

  /// 统一分数滑条（默认 95）。
  double _uniform = 95;

  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final form = await widget.api.fetchForm(widget.target);
      // 本机记下的「上次我打的分」优先级最高：教务对已保存的评教不回填分数
      final local = await EvaluationLocalScores.read(widget.target);
      if (!mounted) return;
      setState(() {
        _form = form;
        _loading = false;
        if (_scores.isEmpty) {
          final base = initialScoresFor(form, local: local, fallback: _uniform);
          _scores.addAll(base);
          // 统一分数滑条也落到「当前这套分的代表值」，别再固定显示 95
          if (base.isNotEmpty) _uniform = base.values.first;
        }
      });
    } on EvaluateError catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _applyUniform(double value) {
    final form = _form;
    if (form == null) return;
    setState(() {
      _uniform = value;
      _scores
        ..clear()
        ..addAll(presetScores(form, value));
    });
  }

  double get _total {
    final form = _form;
    if (form == null) return 0;
    return form.total(_scores);
  }

  int get _filled => _form == null
      ? 0
      : _form!.items.where((i) => _scores.containsKey(i.id)).length;

  Future<void> _save({required bool submit}) async {
    final form = _form;
    if (form == null || _busy) return;
    if (_scores.length < form.requiredCount) {
      showErr(
        context,
        '还有 ${form.requiredCount - _filled} 项必填指标没打分',
        title: '不能${submit ? '提交' : '保存'}',
      );
      return;
    }
    if (submit) {
      final ok = await _confirmSubmit();
      if (ok != true) return;
    }
    setState(() => _busy = true);
    try {
      final warn = await widget.api.precheck(form, _total);
      if (warn.isNotEmpty) {
        if (!mounted) return;
        showErr(context, warn, title: '教务提示');
        return;
      }
      final text = submit
          ? await widget.api.submitForm(
              form,
              _scores,
              comment: _comment.text.trim(),
            )
          : await widget.api.saveForm(
              form,
              _scores,
              comment: _comment.text.trim(),
            );
      // 本地也留一份：下次打开默认显示这套分数
      await EvaluationLocalScores.write(widget.target, _scores);
      // 返回值不可信：以列表 / 汇总为准再核一遍
      final verdict = await _verify(submit: submit);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(verdict.ok ? (submit ? '已提交' : '已保存') : '结果未确认'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                text.isEmpty ? '教务没有返回文案' : text,
                style: const TextStyle(fontSize: 13, height: 1.6),
              ),
              const SizedBox(height: 8),
              Text(
                verdict.detail,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.6,
                  color: SemColors.textMuted,
                ),
              ),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
      await widget.onChanged();
      if (!mounted) return;
      if (verdict.ok) {
        // 保存/提交完成后**留在本页**：用户常要接着改下一项或核对；
        // 只有「提交」不可逆，才顺手退回列表（列表会显示已提交）。
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(submit ? '已提交，这条不能再改了' : '已保存，可以继续调整'),
            duration: const Duration(seconds: 2),
          ),
        );
        if (submit) Navigator.of(context).maybePop();
      }
    } on EvaluateError catch (e) {
      if (mounted) showErr(context, e, title: '操作失败');
    } catch (e) {
      if (mounted) showErr(context, e, title: '操作失败');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 写完复查：拉一次列表，看这一条的状态有没有真的变。
  Future<({bool ok, String detail})> _verify({required bool submit}) async {
    try {
      final targets = await widget.api.fetchTargets();
      final match =
          targets.where((t) => t.jxbId == widget.target.jxbId).toList();
      if (match.isEmpty) {
        return (ok: false, detail: '复查时这条教学班已不在待评列表里，请回列表确认');
      }
      final now = match.first;
      final ok = submit ? now.submitted : (now.saved || now.submitted);
      return (
        ok: ok,
        detail: ok
            ? '复查通过：教务显示「${now.statusLabel}」'
            : '教务返回值像成功，但复查显示仍是「${now.statusLabel}」——数据可能被服务端丢弃，请稍后再试或联系教务',
      );
    } catch (e) {
      return (ok: false, detail: '复查失败：$e');
    }
  }

  Future<bool?> _confirmSubmit() => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('确认提交评教？'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${widget.target.teacher} · ${widget.target.course}',
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              const Text(
                '提交后不能修改，也不可撤销。评教是匿名：教师看不到你的具体打分。',
                style: TextStyle(fontSize: 12.5, height: 1.7),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('再想想'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('确认提交'),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final form = _form;
    return ListenableBuilder(
      listenable: AppState.I,
      builder: (context, _) {
        // 两处留白都要在建 Scaffold 之前算（body 里的 MediaQuery 已被扣过一遍）
        final topInset = glassTopInset(context);
        final bottomInset = glassBottomInset(context);
        return Scaffold(
          extendBodyBehindAppBar: glassTopBarEnabled,
          extendBody: glassBottomBarEnabled && form != null && _error == null,
          appBar: glassAppBar(
            context,
            title: Text(widget.target.course, overflow: TextOverflow.ellipsis),
          ),
          // 留白必须进视图内 ListView 的 padding：内容要从顶栏 / 底栏底下穿过去（issue #15）。
          body: GlassFadedBody(
            barHeight: topInset,
            child: _loading
                ? Padding(
                    padding: EdgeInsets.only(top: topInset),
                    child: const Center(child: CircularProgressIndicator()),
                  )
                : (_error != null
                    ? Padding(
                        padding: EdgeInsets.only(top: topInset),
                        child: _errorView(),
                      )
                    : (form == null
                        ? const SizedBox.shrink()
                        : _formView(form, topInset, bottomInset))),
          ),
          bottomNavigationBar: form == null || _error != null
              ? null
              : glassBottomBar(context, child: _actionBar()),
        );
      },
    );
  }

  Widget _errorView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 40, color: SemColors.textMuted),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.7,
                  color: SemColors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: _load, child: const Text('重试')),
            ],
          ),
        ),
      );

  Widget _formView(EvalForm form, double topInset, double bottomInset) => ListView(
        padding: evaluateFormListPadding(topInset, bottomInset: bottomInset),
        children: [
          if (_busy && _log.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _log,
                      style:
                          TextStyle(fontSize: 11.5, color: SemColors.textMuted),
                    ),
                  ),
                ],
              ),
            ),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.target.teacher,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.target.course +
                                (widget.target.className.isEmpty
                                    ? ''
                                    : ' · ${widget.target.className}'),
                            style: TextStyle(
                              fontSize: 12,
                              color: SemColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Capsule(
                      widget.target.statusLabel,
                      color: widget.target.submitted
                          ? SemColors.success
                          : SemColors.accent,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Text(
                      '统一分数',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: SemColors.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _uniform.toInt().toString(),
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: SemColors.accent,
                      ),
                    ),
                    Text(
                      ' 分',
                      style:
                          TextStyle(fontSize: 12, color: SemColors.textMuted),
                    ),
                  ],
                ),
                Slider(
                  value: _uniform,
                  min: 0,
                  max: 100,
                  divisions: 20,
                  label: _uniform.toInt().toString(),
                  onChanged: _busy ? null : (v) => _applyUniform(v),
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final v in const [100.0, 95.0, 90.0, 80.0, 60.0])
                      ActionChip(
                        label: Text(
                          '${v.toInt()} 分',
                          style: const TextStyle(fontSize: 11.5),
                        ),
                        onPressed: _busy ? null : () => _applyUniform(v),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '总分预览：${_total.toStringAsFixed(2)} / 100　已填 $_filled / ${form.count} 项',
                  style: TextStyle(fontSize: 11.5, color: SemColors.textMuted),
                ),
              ],
            ),
          ),
          for (var gi = 0; gi < form.models.length; gi++)
            for (var g = 0; g < form.models[gi].groups.length; g++)
              _groupCard(form.models[gi], form.models[gi].groups[g]),
          AppCard(
            child: GlassField(
              label: '评语（选填，${form.commentMax} 字以内）',
              controller: _comment,
              maxLines: 4,
              hintText: '可以写下对本课程的建议',
            ),
          ),
          PageNotes(
            lines: const [
              '评教是匿名的：教师看不到你的具体打分，只看到汇总结果。',
              '保存可以反复覆盖，提交之后不能修改，也不能撤销。',
            ],
          ),
        ],
      );

  Widget _groupCard(EvalModel model, EvalGroup group) {
    final title = group.title.isEmpty ? model.name : group.title;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title.isNotEmpty) ...[
            Text(
              title,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: SemColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
          ],
          for (var i = 0; i < group.items.length; i++)
            _itemRow(group.items[i], i + 1),
        ],
      ),
    );
  }

  Widget _itemRow(EvalItem item, int number) {
    final value = _scores[item.id] ?? item.min;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  '$number. ${item.title}',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.45,
                    color: SemColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 44,
                child: Text(
                  value.toInt().toString(),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: SemColors.accent,
                  ),
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            ),
            child: Slider(
              value: item.snap(value),
              min: item.min,
              max: item.max,
              divisions: ((item.max - item.min) / 5).clamp(1, 100).round(),
              label: value.toInt().toString(),
              onChanged: _busy
                  ? null
                  : (v) => setState(() => _scores[item.id] = item.snap(v)),
            ),
          ),
        ],
      ),
    );
  }

  /// 操作条内容（安全区与玻璃胶囊由 [glassBottomBar] 提供）。
  Widget _actionBar() => SizedBox(
        height: 44,
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : () => _save(submit: false),
                icon: const Icon(Icons.save_outlined, size: 18),
                label: const Text('保存'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                onPressed: _busy ? null : () => _save(submit: true),
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_rounded, size: 18),
                label: const Text('提交评教'),
              ),
            ),
          ],
        ),
      );
}
