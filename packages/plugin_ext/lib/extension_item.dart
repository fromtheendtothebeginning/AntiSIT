import 'dart:convert';

/// 一条拓展：名字 + 打开内容（远程网址，或导入的压缩包入口）。
///
/// App 端不内置拓展——清单默认只有 [kBuiltinExtensions]（编译前固定，默认为空），
/// 其余全靠用户自己加（见 [ExtensionStore]）或从插件市场装（[fromMarket]）。
class ExtensionItem {
  const ExtensionItem({
    required this.id,
    required this.name,
    required this.url,
    this.desc = '',
    this.icon = '',
    this.bundled = false,
    this.builtin = false,
    this.version = '',
    this.sha256 = '',
    this.permissions = const [],
    this.fromMarket = false,
    this.sourceId = '',
  });

  /// 稳定 id：生成一次就跟着数据走（存储、每个拓展的键值数据隔离都按它）。
  /// **接口改名称不改 id**：卡片上显示的名字可以变，存储与隔离仍按 id。
  final String id;
  final String name;

  /// 接口（`card.setName` / `card.setDesc` / `card.setIcon`）的长度上限，
  /// 与卡片上的位置对应：名称一行、简介两行、文字图标一个小方块。
  static const int nameMaxLength = 20;
  static const int descMaxLength = 60;
  static const int iconTextMaxLength = 4;

  /// 打开内容：远程拓展是 http(s) 网址；压缩包导入的是本地**入口 html 的绝对路径**。
  final String url;

  /// 简介：显示在卡片名称下方（可空）。
  final String desc;

  /// 自定义图标：一个图片网址，或一段短文字 / emoji（空 = 用网站 favicon）。
  final String icon;

  /// 来自导入的压缩包（[url] 是本地入口文件路径，不是网址）。
  final bool bundled;

  /// 编译前固定的内置拓展：随包发布，用户不能删、不能改（接口仍可改卡片显示值，
  /// 见 [ExtensionStore.setCard]）。
  final bool builtin;

  /// 市场里装的才有：清单里的版本号（`''` = 不是市场装的 / 没写版本）。
  /// 更新判定看它——版本变了，或者同版本但 [sha256] 变了（作者重发了同一版），
  /// 都算「有更新」。
  final String version;

  /// 市场里装的才有：这份内容的 sha256（清单里记的那个值，装的时候校验过）。
  final String sha256;

  /// 市场清单里声明的权限（`storage` / `network` 这类敏感接口）。
  /// **只对 [fromMarket] 的拓展生效**：声明了才放行，没声明就拒（见 `ExtBridge`）。
  final List<String> permissions;

  /// 来自插件市场。市场装的拓展内容来自别人，接口按 [permissions] 放行；
  /// 用户自己填网址 / 自己挑压缩包装的照旧能用全套接口（来源是他自己选的）。
  final bool fromMarket;

  /// 装它的是哪个源：官方目录是 `''`，第三方源是那个源的 id。
  /// 用来挡住「另一个源拿同一个 id 把已装的插件顶掉」——同一 id 换源装会被拒。
  final String sourceId;

  /// 自定义图标是不是图片网址（否则按文字 / emoji 渲染）。
  bool get iconIsImage =>
      icon.startsWith('http://') || icon.startsWith('https://');

  /// 换几个字段（其余原样带走）——[withCard] 与编辑弹窗都走它，
  /// 免得新增字段时漏掉某处拷贝（市场字段就是这么丢过一次也不该丢）。
  ExtensionItem copyWith({
    String? name,
    String? url,
    String? desc,
    String? icon,
    bool? bundled,
    String? version,
    String? sha256,
    List<String>? permissions,
    bool? fromMarket,
    String? sourceId,
  }) =>
      ExtensionItem(
        id: id,
        name: name ?? this.name,
        url: url ?? this.url,
        desc: desc ?? this.desc,
        icon: icon ?? this.icon,
        bundled: bundled ?? this.bundled,
        builtin: builtin,
        version: version ?? this.version,
        sha256: sha256 ?? this.sha256,
        permissions: permissions ?? this.permissions,
        fromMarket: fromMarket ?? this.fromMarket,
        sourceId: sourceId ?? this.sourceId,
      );

  /// 换掉卡片上的显示值（网页用 `card.setName` / `card.setDesc` / `card.setIcon` 接口改，
  /// 见 [ExtensionStore.setCard]）；只传要换的字段，null = 保持原值。
  ExtensionItem withCard({String? name, String? desc, String? icon}) =>
      copyWith(name: name, desc: desc, icon: icon);

  /// 卡片副标题那行：市场装的写来源与版本、本地包说明来源，远程拓展直接写网址
  /// （要不要显示这一行由「拓展」页右上角的总开关决定，见 ExtensionStore.hideUrls）。
  String get urlLine {
    if (!bundled) return url;
    if (!fromMarket) return '本地导入的压缩包';
    return version.isEmpty ? '插件市场' : '插件市场 · v$version';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'url': url,
        if (desc.isNotEmpty) 'desc': desc,
        if (icon.isNotEmpty) 'icon': icon,
        if (bundled) 'bundled': true,
        if (version.isNotEmpty) 'version': version,
        if (sha256.isNotEmpty) 'sha256': sha256,
        if (permissions.isNotEmpty) 'permissions': permissions,
        if (fromMarket) 'market': true,
        if (sourceId.isNotEmpty) 'source': sourceId,
        // builtin 不落盘：只有编译前的固定清单能置这个标记
      };

  /// 生成一个 id。
  static String newId() =>
      'e${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';

  /// 用户手输的网址：没写协议按 https 补；必须能解析出 http(s) 的 host，否则不算数。
  static String? normalizeUrl(String input) {
    var s = input.trim();
    if (s.isEmpty) return null;
    if (!s.contains('://')) s = 'https://$s';
    final uri = Uri.tryParse(s);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) return null;
    if (uri.host.isEmpty) return null;
    return uri.toString();
  }

  /// 解析一条（导入 / 落盘回读）：缺 id 现生成、缺名字用域名、网址必须合法；
  /// `builtin` 一律忽略（只有编译前的固定清单能是内置）。
  /// 市场字段（version / sha256 / permissions / market）缺省即为「不是市场装的」——
  /// 老版本的落盘数据就是这么读回来的。
  static ExtensionItem parse(Object? raw) {
    if (raw is! Map) throw const FormatException('每条拓展要是一个 JSON 对象');
    final bundled = raw['bundled'] == true;
    final rawUrl = '${raw['url'] ?? ''}'.trim();
    // 本地包存的是入口文件路径，不走网址校验；远程拓展必须能当网址用
    final url = bundled ? rawUrl : normalizeUrl(rawUrl);
    if (url == null || url.isEmpty) {
      throw FormatException('网址不对：${rawUrl.isEmpty ? '（空）' : rawUrl}');
    }
    final name = '${raw['name'] ?? ''}'.trim();
    final id = '${raw['id'] ?? ''}'.trim();
    final perms = raw['permissions'];
    return ExtensionItem(
      id: id.isEmpty ? newId() : id,
      name: name.isEmpty ? (bundled ? '本地拓展' : Uri.parse(url).host) : name,
      url: url,
      desc: '${raw['desc'] ?? ''}'.trim(),
      icon: '${raw['icon'] ?? ''}'.trim(),
      bundled: bundled,
      version: '${raw['version'] ?? ''}'.trim(),
      sha256: '${raw['sha256'] ?? ''}'.trim(),
      permissions: perms is List ? [for (final p in perms) '$p'] : const [],
      fromMarket: raw['market'] == true,
      sourceId: '${raw['source'] ?? ''}'.trim(),
    );
  }

  /// 导入入口：接受单条对象，也接受一个数组；空数组 / 坏 JSON 直接抛错。
  static List<ExtensionItem> parseImported(String text) {
    final raw = jsonDecode(text);
    final list = raw is List ? raw : [raw];
    if (list.isEmpty) throw const FormatException('没有可导入的拓展');
    return [for (final e in list) ExtensionItem.parse(e)];
  }
}
