import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'harness.dart';

void main() {
  setUpExtensionEnv();

  group('卡片尺寸', () {
    ExtensionItem item(String id, String name) =>
        ExtensionItem(id: id, name: name, url: 'https://$id.example.com');

    test('默认 2x3；改过的落盘、重开读回；删掉不残留；重置清空', () async {
      final store = ExtensionStore.I;
      await store.load();
      await store.add(item('a', '甲'));
      await store.add(item('b', '乙'));
      expect(store.sizeOf('a'), GridCardSize.standard);
      expect(store.hasCustomSizes, isFalse);

      await store.setSize('a', GridCardSize.wide);
      await store.setSize('b', GridCardSize.tall);
      expect(store.sizeOf('a'), GridCardSize.wide);

      final sp = await SharedPreferences.getInstance();
      expect(jsonDecode(sp.getString('plugin.ext.sizes')!), {
        'a': '1x3',
        'b': '2x2',
      });

      ExtensionStore.I = ExtensionStore(); // 模拟重启
      await ExtensionStore.I.load();
      expect(ExtensionStore.I.sizeOf('a'), GridCardSize.wide);
      expect(ExtensionStore.I.sizeOf('b'), GridCardSize.tall);
      expect(ExtensionStore.I.sizeOf('ghost'), GridCardSize.standard);

      // 删拓展时把它的尺寸一起清掉
      await ExtensionStore.I.remove('a');
      expect(ExtensionStore.I.hasCustomSizes, isTrue);
      expect(jsonDecode(sp.getString('plugin.ext.sizes')!), {'b': '2x2'});

      await ExtensionStore.I.resetSizes();
      expect(ExtensionStore.I.hasCustomSizes, isFalse);
      expect(sp.getString('plugin.ext.sizes'), isNull);
    });

    test('坏数据 / 已删拓展 / 认不出的尺寸按默认处理', () async {
      SharedPreferences.setMockInitialValues({
        'plugin.ext.sizes': '{"a":"9x9","ghost":"1x3","b":"2x2"}',
      });
      final store = ExtensionStore.I;
      await store.load();
      await store.add(item('a', '甲'));
      await store.add(item('b', '乙'));
      await store.load();
      expect(store.sizeOf('a'), GridCardSize.standard);
      expect(store.sizeOf('b'), GridCardSize.tall);
      expect(store.hasCustomSizes, isTrue);

      SharedPreferences.setMockInitialValues({'plugin.ext.sizes': '{oops'});
      final broken = ExtensionStore.I;
      await broken.load();
      expect(broken.hasCustomSizes, isFalse);
    });

    testWidgets('拓展页长按卡片进入整理态，拖弧线改大小并落到本地', (tester) async {
      await PluginRegistry.I.enable('ext');
      await ExtensionStore.I.add(item('a', '甲'));
      await ExtensionStore.I.add(item('b', '乙'));
      await pumpPage(tester);

      final press = await tester.startGesture(
        tester.getCenter(find.text('甲').first),
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(
        find.byKey(const ValueKey<String>('card-size-bar')),
        findsOneWidget,
        reason: '长按进入整理态，出现尺寸条',
      );
      // 尺寸条在页面下方（底栏上方），不是顶栏那块
      final barTop = tester.getTopLeft(
        find.byKey(const ValueKey<String>('card-size-bar')),
      );
      expect(
        barTop.dy,
        greaterThan(
          tester.view.physicalSize.height / tester.view.devicePixelRatio / 2,
        ),
        reason: '尺寸条在页面下半部分',
      );
      await press.up();
      await tester.pumpAndSettle();
      expect(
        find.text('卡片大小 · 2×3'),
        findsOneWidget,
        reason: '长按的「甲」自动成为尺寸条作用对象',
      );

      final handle = find.byKey(const ValueKey<String>('fgrid-handle:a'));
      expect(handle, findsOneWidget);
      // 往左拖 70：宽度 185 → 115，最近的是 2×2（120×128）
      await tester.drag(handle, const Offset(-70, 0));
      await tester.pumpAndSettle();

      expect(ExtensionStore.I.sizeOf('a'), GridCardSize.tall);
      expect(find.text('卡片大小 · 2×2'), findsOneWidget);
      final sp = await SharedPreferences.getInstance();
      expect(sp.getString('plugin.ext.sizes'), contains('"a":"2x2"'));

      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey<String>('card-size-bar')), findsNothing);
    });

    testWidgets('拓展页顶部尺寸条：1×1 / 1×3 / 2×3 / 2×2 直接切换并落到本地', (tester) async {
      await PluginRegistry.I.enable('ext');
      await ExtensionStore.I.add(item('a', '甲'));
      await ExtensionStore.I.add(item('b', '乙'));
      await pumpPage(tester);

      final press = await tester.startGesture(
        tester.getCenter(find.text('甲').first),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await press.up();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('card-size-bar')),
        findsOneWidget,
      );

      final chip1x1 = find.byKey(
        const ValueKey<String>('card-size-option:1x1'),
      );
      await tester.tap(chip1x1);
      await tester.pumpAndSettle();
      expect(ExtensionStore.I.sizeOf('a'), GridCardSize.single);
      expect(find.text('卡片大小 · 1×1'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey<String>('card-size-option:2x2')),
      );
      await tester.pumpAndSettle();
      expect(ExtensionStore.I.sizeOf('a'), GridCardSize.tall);

      await tester.tap(
        find.byKey(const ValueKey<String>('card-size-option:2x3')),
      );
      await tester.pumpAndSettle();
      expect(ExtensionStore.I.sizeOf('a'), GridCardSize.standard);

      final sp = await SharedPreferences.getInstance();
      expect(
        sp.getString('plugin.ext.sizes'),
        isNull,
        reason: '改回默认 2×3 后不残留条目',
      );
    });

    testWidgets('窄屏（360）上 1x3 / 2x2 / 需升级 App 徽章都不溢出', (tester) async {
      final savedLoader = ExtensionItem.appVersionLoader;
      ExtensionItem.appVersionLoader = () async => '1.0.0';
      addTearDown(() => ExtensionItem.appVersionLoader = savedLoader);
      tester.view.physicalSize = const Size(720, 1600);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      await PluginRegistry.I.enable('ext');
      await ExtensionStore.I.add(
        const ExtensionItem(
          id: 'a',
          name: '窄卡',
          url: 'https://a.example.com/x',
          desc: '按教学楼和节次查当前空闲的教室，数据来自教务系统，支持上午下午晚上三段查询',
        ),
      );
      await ExtensionStore.I.add(
        const ExtensionItem(
          id: 'b',
          name: '矮卡',
          url: 'https://b.example.com/y',
          desc: '一段很长的简介，用来撑矮宽卡片的三行排版',
        ),
      );
      await ExtensionStore.I.add(
        const ExtensionItem(
          id: 'c',
          name: '未来拓展',
          url: 'https://c.example.com/z',
          minAppVersion: '9.9.9',
        ),
      );
      await ExtensionStore.I.add(
        const ExtensionItem(
          id: 'd',
          name: '一格卡',
          url: 'https://d.example.com/w',
        ),
      );
      await ExtensionStore.I.setSize('a', GridCardSize.wide);
      await ExtensionStore.I.setSize('b', GridCardSize.tall);
      await ExtensionStore.I.setSize('d', GridCardSize.single);

      await tester.pumpWidget(const MaterialApp(home: ExtensionsPage()));
      await tester.pumpAndSettle();

      expect(
        tester.takeException(),
        isNull,
        reason: '1x1 / 1x3 / 2x2 / 「需升级 App」徽章都不能溢出',
      );
      expect(find.text('需升级 App'), findsOneWidget);
      expect(find.text('窄卡'), findsOneWidget);
      expect(find.text('矮卡'), findsOneWidget);
      // 1x1 只画图标（放名字会被截断），按卡片 key 断言
      expect(find.byKey(const ValueKey<String>('fgrid:d')), findsOneWidget);
      expect(find.text('一格卡'), findsNothing, reason: '1x1 这档只显示图标');
    });
  });
}

