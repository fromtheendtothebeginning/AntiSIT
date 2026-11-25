import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

void main() {
  setUpExtensionEnv();

  group('网站图标', () {
    test('.ico 里嵌的 PNG 帧能抠出来（Flutter 自己解不了 .ico，这是没显示出来的原因）', () {
      final png = fakePng();
      final ico = icoWithFrame(png);
      expect(SiteIcon.isIco(ico), isTrue);
      expect(SiteIcon.pngFrameOfIco(ico), png, reason: '抠出那一帧 PNG');

      expect(SiteIcon.isIco(png), isFalse);
      expect(SiteIcon.pngFrameOfIco(png), isNull);
      expect(
        SiteIcon.pngFrameOfIco(
          icoWithFrame(Uint8List.fromList(const [0x28, 0, 0, 0])),
        ),
        isNull,
        reason: '老式 DIB 帧不硬解，退回首字徽章',
      );
    });

    test('候选地址：apple-touch-icon 优先、相对地址按页面解析、跳过 svg、站点根兜底', () {
      const origin = 'https://a.example.com';
      final page = Uri.parse('$origin/app/index.html');
      final urls = SiteIcon.iconCandidates(
        html:
            '<link rel="apple-touch-icon" href="/touch.png">'
            '<link rel="icon" type="image/svg+xml" href="/a.svg">'
            '<link rel="icon" href="favicon.png">'
            '<link rel="shortcut icon" href="/fav.ico">',
        page: page,
        origin: origin,
      );
      final all = urls.map((u) => u.toString()).toList();
      expect(
        all.first,
        '$origin/touch.png',
        reason: 'apple-touch-icon 最清楚，排最前',
      );
      expect(all, contains('$origin/app/favicon.png'), reason: '相对地址按页面地址解析');
      expect(
        all.any((u) => u.endsWith('.svg')),
        isFalse,
        reason: 'Flutter 不认 svg，跳过',
      );
      expect(all.last, '$origin/favicon.ico', reason: '站点根兜底');
      expect(
        SiteIcon.iconCandidates(page: page, origin: origin).single.toString(),
        '$origin/favicon.ico',
        reason: '页面抓不到也要有兜底',
      );
    });
  });
}

