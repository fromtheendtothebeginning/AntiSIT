import 'package:flutter/material.dart';

import 'package:campus_core/campus_core.dart';

import '../update_check.dart';
import '../widgets/update_dialog.dart';

/// 检查更新二级页：本机版本、稳定版与内测版各自的最新版本，渠道切换与弹窗开关。
class UpdateCenterPage extends StatefulWidget {
  const UpdateCenterPage({super.key, this.autoPrompt = true});

  /// 进页面查到新版本时是否自动弹引导弹窗（官网截图等场景传 false）。
  final bool autoPrompt;

  @override
  State<UpdateCenterPage> createState() => _UpdateCenterPageState();
}

class _UpdateCenterPageState extends State<UpdateCenterPage> {
  @override
  void initState() {
    super.initState();
    _autoCheck();
  }

  /// 查一次各渠道的最新版本。
  Future<void> _refresh() async {
    await UpdateChecker.I.load();
    await UpdateChecker.I.check();
  }

  /// 查到新版本就弹引导（弹窗提醒关掉、或用户点过「稍后」时不弹）。
  Future<void> _promptIfAny() async {
    if (!mounted) return;
    final info = UpdateChecker.I.available;
    if (info != null && UpdateChecker.I.shouldPrompt) {
      await showUpdateDialog(context, info);
    }
  }

  /// 进页面自动查一次：用户点「检查更新」进来就是为了看有没有新版。
  Future<void> _autoCheck() async {
    await _refresh();
    if (widget.autoPrompt) await _promptIfAny();
  }

  Future<void> _manualCheck() async {
    await _refresh();
    if (!mounted) return;
    final uc = UpdateChecker.I;
    if (uc.error != null) {
      showErr(context, '检查更新失败：${uc.error}', title: '检查更新失败');
      return;
    }
    if (uc.available != null) {
      await _promptIfAny();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已是${channelLabel(uc.channel)}的最新版本'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// 更新到某个渠道的某个版本：版本比本机新就直接走引导弹窗（含应用内下载）。
  Future<void> _updateTo(UpdateInfo info) => showUpdateDialog(context, info);

  /// 切到另一个渠道；切过去之后如果那条渠道也有新版本，就把引导弹窗一起弹出来。
  Future<void> _switchTo(UpdateChannel c) async {
    await UpdateChecker.I.setChannel(c);
    await _promptIfAny();
  }

  @override
  Widget build(BuildContext context) {
    final topInset = glassTopInset(context);
    return ListenableBuilder(
      listenable: UpdateChecker.I,
      builder: (context, _) {
        final uc = UpdateChecker.I;
        return Scaffold(
          extendBodyBehindAppBar: glassTopBarEnabled,
          appBar: glassAppBar(
            context,
            title: const Text('检查更新'),
            actions: [
              if (uc.checking)
                const Padding(
                  padding: EdgeInsets.only(right: 16),
                  child: Center(
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              else
                IconButton(
                  onPressed: _manualCheck,
                  icon: const Icon(Icons.refresh_rounded),
                  tooltip: '立即检查',
                ),
            ],
          ),
          body: GlassFadedBody(
            barHeight: topInset,
            child: ListView(
              padding: EdgeInsets.fromLTRB(12, 4 + topInset, 12, 24),
              children: [
                _currentCard(context, uc),
                const SizedBox(height: 10),
                _channelCard(context, uc),
                const SizedBox(height: 10),
                AppCard(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: SwitchListTile(
                    secondary: const Icon(Icons.notifications_active_outlined),
                    title: const Text('新版本弹窗提醒'),
                    subtitle: const Text(
                      '查到的版本比你装的新时弹窗提示；关掉后只在打开本页时显示',
                      style: TextStyle(fontSize: 12),
                    ),
                    value: uc.promptEnabled,
                    onChanged: (v) => UpdateChecker.I.setPromptEnabled(v),
                  ),
                ),
                const SizedBox(height: 10),
                const PageNotes(
                  lines: [
                    '稳定版只跟随正式发布；内测版会收到开发中的版本，可能不稳定。',
                    '换渠道不换安装包：内测版装过的版本可以直接用稳定版同版本号覆盖，不需要卸载。',
                    '应用内更新会先校验 .sha256 再核对包名与签名，装完自动删除安装包。',
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _currentCard(BuildContext context, UpdateChecker uc) {
    final version = uc.current.isEmpty ? '—' : 'v${uc.current}';
    final error = uc.error;
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.phone_android_rounded),
            title: const Text('当前版本'),
            subtitle: Text(
              error != null
                  ? '检查更新失败：$error'
                  : (uc.lastCheck == null
                        ? '正在检查…'
                        : '$version · ${channelLabel(uc.channel)}'),
              style: TextStyle(
                fontSize: 12,
                color: error != null ? SemColors.danger : null,
              ),
            ),
            trailing: Text(
              version,
              style: TextStyle(fontSize: 13, color: SemColors.textMuted),
            ),
          ),
          if (uc.lastCheck != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '上次检查：${_hm(uc.lastCheck!)}',
                  style: TextStyle(fontSize: 11, color: SemColors.textMuted),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _channelCard(BuildContext context, UpdateChecker uc) {
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          for (final c in UpdateChannel.values)
            _channelRow(
              context,
              uc,
              c,
              divider: c != UpdateChannel.values.last,
            ),
        ],
      ),
    );
  }

  Widget _channelRow(
    BuildContext context,
    UpdateChecker uc,
    UpdateChannel c, {
    bool divider = false,
  }) {
    final selected = uc.channel == c;
    final latest = uc.latestFor(c);
    final update = uc.availableFor(c);
    final waiting = uc.checking && latest == null;
    // 内测版借用了稳定版那一份时，两点一线：别把同一个版本说成「两条渠道各有新版」。
    final shared = c == UpdateChannel.dev && uc.devSharesStable;
    final status = update != null
        ? (shared
              ? '有新版本 v${update.version}（与稳定版相同）'
              : '有新版本 v${update.version}')
        : (latest != null
              ? (shared
                    ? '与稳定版同一版本'
                    : (c == UpdateChannel.dev && uc.stableLatest != null
                          ? '最新 v${latest.version}'
                          : '已是最新'))
              : (waiting ? '检查中…' : (uc.error == null ? '暂无版本信息' : '检查失败')));
    return Column(
      children: [
        ListTile(
          leading: Icon(
            c == UpdateChannel.stable
                ? Icons.verified_outlined
                : Icons.science_outlined,
            color: selected ? SemColors.accent : null,
          ),
          title: Row(
            children: [
              Text(channelLabel(c)),
              if (c == UpdateChannel.dev) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: SemColors.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'BETA',
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: SemColors.accent,
                    ),
                  ),
                ),
              ],
            ],
          ),
          subtitle: Text(
            status,
            style: TextStyle(
              fontSize: 12,
              color: update != null ? SemColors.accent : null,
            ),
          ),
          trailing: update != null
              ? TextButton(
                  onPressed: () => _updateTo(update),
                  child: const Text('更新'),
                )
              : (selected
                    ? Icon(
                        Icons.check_circle,
                        size: 18,
                        color: SemColors.accent,
                      )
                    : TextButton(
                        onPressed: () => _switchTo(c),
                        child: const Text('切换'),
                      )),
          // 点整行也能切渠道：切过去之后自动提示那条渠道的新版本
          onTap: selected ? null : () => _switchTo(c),
        ),
        if (divider) const Divider(height: 1, indent: 56, endIndent: 16),
      ],
    );
  }

  String _hm(DateTime t) {
    final now = DateTime.now();
    final diff = now.difference(t);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }
}
