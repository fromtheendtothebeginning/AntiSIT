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
  ChangelogEntry(version: '1.30.0', date: '2026-11-09', notes: [
    '拓展工坊界面重做（参考 DSH Go）：顶栏标题 + 对话 / 文件页签，消息按 markdown 排版',
    '代码块带语言标签与一键复制，连续的工具调用收成一行「已执行 N 个操作」，点开看参数与结果',
    '输入区改成卡片式：计划 / 完全访问放在输入框里，切换草稿与对话收进返回键与「⋯」菜单',
  ]),
  ChangelogEntry(version: '1.29.2', date: '2026-11-09', notes: [
    '拓展页新增自定义排序：标题栏「排序」里按住手柄拖动，宫格立刻跟着变',
    '排序结果存在本机，重启 App 不变；「恢复默认」回原始顺序，新加的拓展排在最后',
  ]),
  ChangelogEntry(version: '1.29.1', date: '2026-11-09', notes: [
    '修复应用内「安装」必定失败：传给系统安装器的参数格式不对，安装器其实从来没被拉起',
    '安装失败时的报错只留关键一行，不再甩一整段堆栈',
  ]),
  ChangelogEntry(version: '1.29.0', date: '2026-11-09', notes: [
    '拓展工坊支持流式输出：正文与思考过程边生成边显示，思考默认折叠、点开可看全文',
    '一个拓展草稿可以开多段对话（新建 / 切换 / 删除），未安装的草稿可直接删除',
    '新增 Agent 技能库：可安装 / 读取 / 删除可复用的指令文档，后续任务按需调用',
    '新增计划模式（只读分析出方案）与完全访问模式（跳过逐次确认），两者可同时开启',
    '拓展工坊界面按 App 风格重做：卡片、胶囊模式开关、底部抽屉与统一配色',
    '拓展页改版：2 列压缩卡片、内置 / 已安装 / 可更新角标、整行虚线「添加拓展」',
  ]),
  ChangelogEntry(version: '1.28.7', date: '2026-11-09', notes: [
    '修复部分机型（ColorOS 等）点击「安装」没反应：补上系统安装确认页的拉起',
    '安装失败不再静默：显示系统返回的真实原因（被拦截 / 签名冲突 / 安装包损坏等），可直接「重试安装」',
  ]),
  ChangelogEntry(version: '1.28.6', date: '2026-11-08', notes: [
    '摄像头与扫一扫拆成两个独立插件：可在「插件管理」里分别查看启停，扫码入口随插件启停显示',
    '扫一扫与 WebView 内核改为插件级关联：内核被停用时，扫出的网址自动改走系统浏览器',
    '扫码打开的活动详情页补齐名称 / 时间等元信息，页面不再开天窗',
  ]),
  ChangelogEntry(version: '1.28.5', date: '2026-11-08', notes: [
    '应用内安装改走系统 PackageInstaller 会话：不依赖 intent 拉起，ColorOS 等 ROM 拦截差异最小',
  ]),
  ChangelogEntry(version: '1.28.4', date: '2026-11-08', notes: [
    '相册识别兼容一张图多个二维码：去重后弹选择面板，点选哪个走哪条流程',
  ]),
  ChangelogEntry(version: '1.28.3', date: '2026-11-08', notes: [
    '扫活动详情码打开的详情页补齐名称 / 时间 / 名额等元信息，页面不再开天窗',
  ]),
  ChangelogEntry(version: '1.28.2', date: '2026-11-08', notes: [
    '应用内更新安装失败时显示真实原因（通道 / 系统拒绝分开标注），便于定位各机型差异',
  ]),
  ChangelogEntry(version: '1.28.1', date: '2026-11-08', notes: [
    '扫一扫新增「活动详情码」适配：扫海报上的报名码直接打开活动详情页报名',
    '更新弹窗在安装包就绪后常驻「用浏览器下载」，装不上也有直接出路',
  ]),
  ChangelogEntry(version: '1.28.0', date: '2026-11-08', notes: [
    '扫一扫新增支持「报名（培训）二维码」：一键完成签到',
    '扫一扫界面改版：底部大按钮 + 手电筒补光，识别只认二维码并自动变焦',
    '扫出的网址改用内置浏览器打开，不再跳系统浏览器',
    '二课扫码签到支持服务器模式',
    '应用内更新安装更稳：缺权限自动跳授权页、授权回来自动续装，失败显示真实原因',
  ]),
  ChangelogEntry(version: '1.27.0', date: '2026-11-08', notes: [
    '扫一扫界面改版：底部大按钮 + 手电筒补光，暗光签到现场也能扫',
    '识别更准：只识二维码、自动变焦，远距离扫码也能对上',
    '扫出的网址改用内置浏览器打开，不再跳系统浏览器',
    '二课扫码签到支持服务器模式（需学校服务器更新后可用，直连不受影响）',
  ]),
  ChangelogEntry(version: '1.26.0', date: '2026-11-07', notes: [
    '新增「扫一扫」：第二课堂活动 / 拓展页右上角进入，相机与相册图片都能识码',
    '识出二课活动签到码时一键完成签到 / 签退，学校判定原文直接展示（需直连）',
    '修复 2026 级新生无法登录教务：账密被拒时自动改走学校官方统一认证 SSO',
    '二课加分明细与活动看板：新增类别标签筛选（一级 / 二级级联）与拼音搜索',
    '发现新版本可直接在应用内下载安装：显示进度、校验 sha256 后拉起安装器',
  ]),
  ChangelogEntry(version: '1.24.0', date: '2026-11-06', notes: [
    '新增「抢课」工具：正方教务 9.0 选课轮次、课程余量与教学班展开',
    '支持自动抢课：名额已满时每 1.5 秒重试，成功或需要人工处理后自动停止',
    '可随时停止并查看已选课程；网络结果不确定时先停下来提示确认，避免重复提交',
    '抢课仅支持直连模式（校园网 / 校内 VPN），服务器模式会显示切换引导',
  ]),
  ChangelogEntry(version: '1.23.1', date: '2026-11-06', notes: [
    '活动广场直接标出「已人满」：满员活动的报名按钮显示「人满，不可报名」，不用提交后才知道',
    '服务器模式的二课活动详情补齐报名人数 / 报名状态，点进详情即可判断满员或条件不符',
  ]),
  ChangelogEntry(version: '1.23.0', date: '2026-11-06', notes: [
    '新增「学业情况」页：平均学分绩点、计划内外课程通过数、培养方案学分要求与类别课程明细',
    '学业情况支持服务器模式；通识类 / 实践环节的非课程明细也能显示',
    '二课累计学分修复浮点尾巴（如 5.930000000000002 → 5.93），明细分页按总数续页并去重',
  ]),
  ChangelogEntry(version: '1.22.0', date: '2026-11-05', notes: [
    '教务登录支持统一身份认证：账号密码被学校拒绝时（如 26 级新生）自动改走统一认证，密码不变',
    '二课活动新增「我的报名」、二课分数新增「加分明细」，与主视图左右滑动切换',
    '二课活动按钮显示「已人满 / 条件不符」；未标注的校区 / 类别标签不再显示',
    '工具页与二级页数据保存到本机，重开 App 也能先看到上次的数据；登录续期不再清空缓存',
    '直连模式的寝室改为「楼号 + 寝室号」分开填写',
    '平均绩点改为一位小数',
  ]),
  ChangelogEntry(version: '1.21.0', date: '2026-11-04', notes: [
    '校园码默认改为每 10 秒换一张，刷新间隔可在「我的 → 配置」调整（5–30 秒）',
    '新增「我的 → 配置」页：工具页自动刷新开关、校园码刷新间隔、第二课堂达标线入口都收在这里',
    '电费 / 二课 / 活动 / 考试 / 成绩页会保留上次数据：进入先显示本地缓存，顶部转圈刷新，新数据到达后自动替换，并可手动刷新',
    '退出登录时清空工具页缓存，换账号不会看到上一个账号的数据',
    '课表课程 / 日程 / 背景表单的校验提示改在弹层内显示，不再被弹层遮住',
  ]),
  ChangelogEntry(version: '1.20.2', date: '2026-10-27', notes: [
    '课表小卡片重新露出教室号：地点拆成楼名与编号，一节课高也能看到 A301',
    '周视图日程按真实时间定位：前后相接的日程不再都挤到同一节次上叠在一起',
    '日程真重叠时改用不透明底色，不再透出下面那张卡的文字',
  ]),
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
