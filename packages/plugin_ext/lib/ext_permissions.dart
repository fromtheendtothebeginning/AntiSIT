/// 拓展权限：哪些接口要在 `ext.json` 里声明、怎么跟用户说明。
///
/// 分两档：
/// * **基础接口**（配色 / 提示 / 关页 / 改自己的卡片）——只跟界面有关，**永远放行**，
///   不声明也不用声明；
/// * **敏感接口**（`storage` 读写自己的数据、`network` 运行时联网）——市场装的拓展
///   **必须声明**，安装时列给用户看；没声明就调用 → 直接拒（见 `ExtBridge`）。
///
/// 诚实边界：这是**防误用**，不是沙箱。声明了 `storage` 的网页照样能读写它自己那份存储；
/// 网页本身仍跑在不受限的 WebView 里。真正的隔离在「App 的用户数据不进这套接口」那一步。
library;

/// 敏感权限：市场清单里必须声明才会被放行。
const Set<String> kSensitivePermissions = {'storage', 'network', 'ai'};

/// 权限的中文说明（与市场仓库 `market_manifest.dart` 的文案保持一致）。
const Map<String, String> kPermissionLabels = {
  'storage': '在本机保存数据（记设置、记历史）',
  'network': '运行时联网',
  'ai': '调用 AI 对话（用你配置的模型与 API Key，可能产生费用）',
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
};

/// 敏感权限的中文说明列表（市场页 / 安装弹窗 / 详情页共用）。
List<String> describeSensitivePermissions(Iterable<String> permissions) => [
      for (final p in kSensitivePermissions)
        if (permissions.contains(p)) kPermissionLabels[p] ?? p,
    ];
