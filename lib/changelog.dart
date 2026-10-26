import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'update_check.dart';

/// 一条版本更新日志。
class ChangelogEntry {
  const ChangelogEntry({required this.version, required this.date, required this.notes});

  final String version;

  /// 发布日期（YYYY-MM-DD）。
  final String date;

  /// 面向用户的变更说明（每条一行，弹窗里按 · 列表展示）。
  final List<String> notes;
}

/// 内置更新日志，新版本在最上面。**每次发版在表头加一条**，版本号与 pubspec 的
/// versionName 一致；用户升级后第一次打开 App 时，比他上次见过的版本新的条目会弹窗展示。
const List<ChangelogEntry> appChangelog = [
  ChangelogEntry(version: '1.20.1', date: '2026-10-26', notes: [
    '课表小卡片文字重叠修复：窄屏 1 节课程/日程只保留名称，地点/教师/时间在详情里看；周标题自动缩放',
  ]),
  ChangelogEntry(version: '1.20.0', date: '2026-10-26', notes: [
    '二课分数新增「达标线设置」三级页面：可按年级调整总目标与各板块分数，修改只保存在本机，默认规则不变',
    '直连模式新增「年级（入学年）」填写，用于二课达标线与学期标签；手填优先，未填时用教务返回的年级',
    '达标线支持远端默认配置，后续调整规则不需要更新 App',
  ]),
  ChangelogEntry(version: '1.19.2', date: '2026-10-26', notes: [
    '课表周视图新增 16:30–18:00 晚饭空档行：17:40–18:00 等没有节次时段的日程不再保存后看不见',
  ]),
  ChangelogEntry(version: '1.19.1', date: '2026-10-26', notes: [
    '修复工具页「二课分数」卡面显示 0 / 0（接口返回字符串数值时未解析）',
  ]),
  ChangelogEntry(version: '1.19.0', date: '2026-10-26', notes: [
    '教务导入失败时显示学校返回的真实原因（修复失败原因被误判成「登录页改版」）',
    '成绩、考试、二课、电费、校园卡、拓展市场等组件失败时统一弹窗展示学校 / 服务器返回的原因，可长按复制',
    '验证码换图失败的原因直接显示在验证码弹窗内',
    '更新检查优先从 Gitee 下载，Gitee 不可用时自动回退 GitHub / 镜像',
  ]),
  ChangelogEntry(version: '1.18.1', date: '2026-10-25', notes: [
    '在线报名再简化：去掉自述信息填写，报名内容全部由学校系统预填，确认后直接提交',
  ]),
  ChangelogEntry(version: '1.18.0', date: '2026-10-25', notes: [
    '二课活动详情页新增在线报名：确认后提交，进入学校审批流并返回申请编号；已报名的活动自动显示「已报名」',
    '新增更新日志：升级后首次打开自动展示新版本变化',
    '账号凭据改存系统加密存储；更新检查新增镜像源兜底；若干稳定性修复',
  ]),
  ChangelogEntry(version: '1.17.0', date: '2026-10-23', notes: [
    '拓展中心默认开启，主界面可左右滑动切页',
    '插件市场支持第三方源与卡片简介',
    'AI 对话接口接入，拓展新增最低版本要求门槛',
  ]),
  ChangelogEntry(version: '1.16.1', date: '2026-10-18', notes: [
    '新增插件市场：拓展页「市场」标签，支持安装 / 更新 / 卸载与权限提示',
    '示例拓展：2048 与扫雷',
    '课表导入：混合奇偶周次不再误并；成绩单兼容新学期码',
    'AI 识图：思考型模型空回答时自动关思考重试',
  ]),
  ChangelogEntry(version: '1.15.0', date: '2026-10-13', notes: [
    '新增启动时更新检查：有新版本时弹窗引导更新',
  ]),
];

/// 上次打开时的版本号记在偏好里的键。
const String kChangelogSeenVersion = 'changelog_seen_version';

/// 比上次见过的版本（不含）新、且不晚于当前版本（含）的条目，新版本在前。
/// 首次安装（[since] 为 null）、版本没变、降级安装都返回空。
List<ChangelogEntry> changelogEntriesSince(String? since, String current) {
  if (since == null || since == current) return const [];
  return [
    for (final e in appChangelog)
      if (compareVersions(e.version, since) > 0 && compareVersions(e.version, current) <= 0) e
  ];
}

/// 升级后第一次打开 → 弹更新日志。首次安装不弹（没有「更新」发生，只记下当前版本），
/// 版本没变也不弹。返回是否展示了弹窗。
Future<bool> showChangelogIfUpdated(BuildContext context, String current) async {
  final sp = await SharedPreferences.getInstance();
  final seen = sp.getString(kChangelogSeenVersion);
  if (seen == null) {
    await sp.setString(kChangelogSeenVersion, current);
    return false;
  }
  final entries = changelogEntriesSince(seen, current);
  // 先记再弹：看完关掉就算完，不区分「已读」；降级安装也记下，避免每次启动都弹
  await sp.setString(kChangelogSeenVersion, current);
  if (entries.isEmpty || !context.mounted) return false;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('更新日志'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < entries.length; i++) ...[
                Text('${entries[i].version} · ${entries[i].date}',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                for (final n in entries[i].notes)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text('· $n', style: const TextStyle(fontSize: 13)),
                  ),
                if (i < entries.length - 1) const Divider(height: 20),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('知道了')),
      ],
    ),
  );
  return true;
}
