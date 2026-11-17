import 'dart:convert';

import 'package:crypto/crypto.dart';

/// 发布目标平台。
enum PublishProvider {
  github('GitHub', 'https://github.com/settings/tokens'),
  gitee('Gitee', 'https://gitee.com/profile/personal_access_tokens');

  const PublishProvider(this.label, this.tokenUrl);

  final String label;

  /// 去这里创建 Personal Access Token。
  final String tokenUrl;

  static PublishProvider fromName(String? name) =>
      PublishProvider.values.firstWhere((p) => p.name == name,
          orElse: () => PublishProvider.github);
}

/// 发布设置：发到哪个平台的哪个仓库、哪个分支。
///
/// Token 与签名私钥不在这里——它们走 [SecureStore]（Keystore / Keychain）。
class PublishConfig {
  const PublishConfig({
    required this.provider,
    required this.owner,
    required this.repo,
    this.branch = '',
  });

  final PublishProvider provider;
  final String owner;
  final String repo;

  /// 空 = 用仓库的默认分支。
  final String branch;

  String get repoInput => owner.isEmpty || repo.isEmpty ? '' : '$owner/$repo';

  Map<String, Object?> toJson() => {
        'provider': provider.name,
        'owner': owner,
        'repo': repo,
        if (branch.isNotEmpty) 'branch': branch,
      };

  static PublishConfig? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final owner = '${raw['owner'] ?? ''}'.trim();
    final repo = '${raw['repo'] ?? ''}'.trim();
    if (owner.isEmpty || repo.isEmpty) return null;
    return PublishConfig(
      provider: PublishProvider.fromName('${raw['provider'] ?? ''}'),
      owner: owner,
      repo: repo,
      branch: '${raw['branch'] ?? ''}'.trim(),
    );
  }

  /// 源目录前缀（App 添加源后按 `<base>market.json` 拉目录）。
  /// GitHub 走 jsDelivr（国内可达性好）；Gitee 用官方 raw。
  String sourceBase(String branch) => provider == PublishProvider.github
      ? 'https://cdn.jsdelivr.net/gh/$owner/$repo@$branch/'
      : 'https://gitee.com/$owner/$repo/raw/$branch/';

  /// 直装包地址前缀。与源目录同一个镜像：GitHub 走 jsDelivr（国内可达性好），
  /// 包路径里带版本号，升版本后就是新 URL，不怕 CDN 缓存旧包。
  String zipBase(String branch) => sourceBase(branch);

  /// 分享给别人「添加源」时填的值：GitHub 用 `owner/repo`（App 自动拼 jsDelivr），
  /// Gitee 用完整 raw 地址。
  String sourceInput(String branch) => provider == PublishProvider.github
      ? '$owner/$repo'
      : sourceBase(branch);

  /// 解析用户填的仓库：`owner/repo`、`https://github.com/owner/repo`、
  /// `https://gitee.com/owner/repo`（可带 .git / 尾斜杠）。
  ///
  /// 抛 [FormatException] 时消息可以直接给用户看。
  static PublishConfig parse({
    required PublishProvider provider,
    required String input,
    String branch = '',
  }) {
    var s = input.trim();
    if (s.isEmpty) throw const FormatException('填一下仓库，例如 yourname/antisit-plugins');
    if (s.startsWith('http://') || s.startsWith('https://')) {
      final uri = Uri.tryParse(s);
      if (uri == null || uri.host.isEmpty) {
        throw FormatException('仓库地址不合法：$s');
      }
      final expected = provider == PublishProvider.github ? 'github.com' : 'gitee.com';
      if (uri.host != expected) {
        throw FormatException('这是 ${provider.label} 发布，仓库地址要是 $expected 的');
      }
      s = uri.path;
    }
    s = s.replaceAll(RegExp(r'/+$'), '');
    if (s.endsWith('.git')) s = s.substring(0, s.length - 4);
    final parts = s.split('/').where((p) => p.isNotEmpty).toList();
    if (parts.length != 2 ||
        !RegExp(r'^[\w.-]+$').hasMatch(parts[0]) ||
        !RegExp(r'^[\w.-]+$').hasMatch(parts[1])) {
      throw FormatException('仓库格式不对：要写成 `所有者/仓库`（现在是「$input」）');
    }
    return PublishConfig(
      provider: provider,
      owner: parts[0],
      repo: parts[1],
      branch: branch.trim(),
    );
  }
}

/// 发布成功后的分享信息。
class PublishResult {
  const PublishResult({
    required this.provider,
    required this.owner,
    required this.repo,
    required this.branch,
    required this.sourceInput,
    required this.fingerprint,
    required this.installCode,
    required this.zipUrl,
    required this.id,
    required this.name,
    required this.version,
  });

  final PublishProvider provider;
  final String owner;
  final String repo;
  final String branch;

  /// 别人在「市场 → 添加第三方源」里填的值。
  final String sourceInput;

  /// 发布密钥的公钥指纹（别人添加源时要核对）。
  final String fingerprint;

  /// 直装二维码内容：`{"antisit":"ext","url":…,"sha256":…}`。
  final String installCode;

  final String zipUrl;
  final String id;
  final String name;
  final String version;

  /// 给作者复制的一段分享文案。
  String get shareText => '''
AntiSIT 拓展：$name v$version
直装：用 AntiSIT「拓展 → 扫一扫」扫下方二维码，或复制安装码。
安装码：$installCode

想接收后续更新：在「拓展 → 市场 → 添加第三方源」填
$sourceInput
公钥指纹：$fingerprint（添加时会显示，核对一致再确认）
源二维码：$sourceCode
''';

  /// 源二维码内容：`{"antisit":"source","repo":…,"fingerprint":…}`。
  /// 别人在「市场 → 插件源 → 扫一扫添加源」扫这张码，App 会拉目录并核对指纹。
  String get sourceCode => jsonEncode({
        'antisit': 'source',
        'repo': sourceInput,
        if (branch.isNotEmpty) 'branch': branch,
        if (fingerprint.isNotEmpty) 'fingerprint': fingerprint,
        'name': name,
      });
}

/// 发布签名密钥（Ed25519）。私钥只在本机加密存储里，绝不上传。
class PublishKey {
  const PublishKey({
    required this.keyId,
    required this.privateKey,
    required this.publicKey,
  });

  final String keyId;

  /// base64 的 32 字节种子。
  final String privateKey;

  /// base64 的 32 字节公钥。
  final String publicKey;

  Map<String, Object?> toJson() => {
        'keyId': keyId,
        'privateKey': privateKey,
        'publicKey': publicKey,
      };

  static PublishKey? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final priv = '${raw['privateKey'] ?? ''}'.trim();
    final pub = '${raw['publicKey'] ?? ''}'.trim();
    if (priv.isEmpty || pub.isEmpty) return null;
    return PublishKey(
      keyId: '${raw['keyId'] ?? 'author'}'.trim().isEmpty
          ? 'author'
          : '${raw['keyId']}'.trim(),
      privateKey: priv,
      publicKey: pub,
    );
  }
}

/// 公钥指纹：`sha256(公钥字节)` 的前 12 位十六进制，按 4 位一组。
/// 与市场工具 / App 添加源时的算法完全一致。
String publishKeyFingerprint(String publicKeyBase64) {
  final bytes = base64Decode(publicKeyBase64);
  final hex = sha256.convert(bytes).toString().toUpperCase();
  final head = hex.substring(0, 12);
  return '${head.substring(0, 4)}-${head.substring(4, 8)}-${head.substring(8, 12)}';
}
