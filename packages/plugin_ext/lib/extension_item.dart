import 'dart:convert';

/// 一条拓展：名字 + 打开内容（远程网址，或导入的压缩包入口）。
///
/// App 端不内置拓展——清单默认只有 [kBuiltinExtensions]（编译前固定，默认为空），
/// 其余全靠用户自己加（见 [ExtensionStore]）。
class ExtensionItem {
  const ExtensionItem({
    required this.id,
    required this.name,
    required this.url,
    this.desc = '',
    this.icon = '',
    this.bundled = false,
    this.builtin = false,
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

  /// 自定义图标是不是图片网址（否则按文字 / emoji 渲染）。
  bool get iconIsImage =>
      icon.startsWith('http://') || icon.startsWith('https://');

  /// 换掉卡片上的显示值（网页用 `card.setName` / `setDesc` / `setIcon` 接口改，
  /// 见 [ExtensionStore.setCard]）；只传要换的字段，null = 保持原值。
  ExtensionItem withCard({String? name, String? desc, String? icon}) => ExtensionItem(
        id: id,
        name: name ?? this.name,
        url: url,
        desc: desc ?? this.desc,
        icon: icon ?? this.icon,
        bundled: bundled,
        builtin: builtin,
      );

  /// 卡片副标题那行：本地包说明来源，远程拓展直接写网址
  /// （要不要显示这一行由「拓展」页右上角的总开关决定，见 ExtensionStore.hideUrls）。
  String get urlLine => bundled ? '本地导入的压缩包' : url;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'url': url,
        if (desc.isNotEmpty) 'desc': desc,
        if (icon.isNotEmpty) 'icon': icon,
        if (bundled) 'bundled': true,
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
    return ExtensionItem(
      id: id.isEmpty ? newId() : id,
      name: name.isEmpty ? (bundled ? '本地拓展' : Uri.parse(url).host) : name,
      url: url,
      desc: '${raw['desc'] ?? ''}'.trim(),
      icon: '${raw['icon'] ?? ''}'.trim(),
      bundled: bundled,
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
