/// 拓展权限：哪些接口要在 `ext.json` 里声明、怎么跟用户说明。
///
/// 基础接口（配色 / 提示 / 关页 / 改自己的卡片）永远放行；敏感接口市场装的拓展
/// 必须声明，没声明就调用直接拒。这是**防误用**，不是沙箱——真正的隔离在
/// 「App 的用户数据不进这套接口」那一步。
library;

/// 敏感权限：市场清单里必须声明才会被放行。
const Set<String> kSensitivePermissions = {
  'storage',
  'network',
  'campus_net',
  'ai',
  'notification',
  'secrets',
  'clipboard',
  'login',
  'background',
  'files',
  // 语音输入：系统识别器要录音权限（用户点麦克风时才申请，识别结果只回填输入框）
  'voice',
};

/// 权限的中文说明（与市场仓库 `market_manifest.dart` 的文案保持一致）。
const Map<String, String> kPermissionLabels = {
  'storage': '在本机保存数据（记设置、记历史）',
  'network': '运行时联网',
  'campus_net': '访问校内明文 http 站点（实验系统 / 报告系统这类内网地址）',
  'ai': '调用 AI 对话（用你配置的模型与 API Key，可能产生费用）',
  'notification': '给你发通知（可定时提醒，App 没打开也能收到）',
  'secrets': '保存登录凭据 / Cookie（系统加密存储，按拓展隔离）',
  'clipboard': '读写剪贴板（读取时会再弹一次确认）',
  'login': '打开登录页并读取你声明域名的 Cookie（打开前会再弹一次确认）',
  'background': '在后台保持运行（显示一条常驻通知，可随时停止）',
  'files': '读取 / 保存你选中的文件（只通过系统文件选择器，不会扫描本机文件）',
  'voice': '语音输入（点麦克风时录音识别，结果只填进输入框，录音不保存）',
  'theme': '读取 App 配色（只读）',
  'toast': '弹一条 App 风格的提示',
  'close': '关闭自己的页面',
  'card': '改自己在列表里那张卡片的名字 / 简介 / 图标',
};

/// 接口 → 需要的敏感权限。不在这张表里的方法属于基础接口，永远放行。
/// （`network` 不在这张表里：它管的是页面能不能联网，由内核注入的 CSP 落实。）
const Map<String, String> kMethodPermissions = {
  'storage.get': 'storage',
  'storage.set': 'storage',
  'storage.remove': 'storage',
  'ai.chat': 'ai',
  'ai.chatTools': 'ai',
  'ai.chatToolsStream': 'ai',
  'ai.models': 'ai',
  'ai.current': 'ai',
  'ai.setModel': 'ai',
  'notify.show': 'notification',
  'notify.schedule': 'notification',
  'notify.cancel': 'notification',
  'notify.cancelAll': 'notification',
  'secrets.get': 'secrets',
  'secrets.set': 'secrets',
  'secrets.remove': 'secrets',
  'net.request': 'network',
  'net.campus': 'campus_net',
  'clipboard.read': 'clipboard',
  'clipboard.write': 'clipboard',
  'login.open': 'login',
  'login.clear': 'login',
  'background.keepAlive': 'background',
  'files.pick': 'files',
  'files.save': 'files',
  'voice.start': 'voice',
  'voice.stop': 'voice',
  'voice.cancel': 'voice',
  'voice.available': 'voice',
};

/// 服务名 → 需要的权限：给「源码体检」用（拓展工坊自检、市场 `check` 共用）。
///
/// 只收「一个服务对应一个权限」的：`net`、`files` 各有两种权限 / 文案，单独查。
const Map<String, String> kServicePermissions = {
  'storage': 'storage',
  'secrets': 'secrets',
  'notify': 'notification',
  'clipboard': 'clipboard',
  'login': 'login',
  'background': 'background',
  'ai': 'ai',
  'voice': 'voice',
};

/// 敏感权限的中文说明列表（市场页 / 安装弹窗 / 详情页共用）。
List<String> describeSensitivePermissions(Iterable<String> permissions) => [
      for (final p in kSensitivePermissions)
        if (permissions.contains(p)) kPermissionLabels[p] ?? p,
    ];
