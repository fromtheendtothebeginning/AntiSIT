import 'package:campus_core/campus_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_score/plugin_score.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 工具页缓存必须落闪存：进程被杀 / 隔一段时间再进来，卡面和二级页都直接有上次的数据，
/// 而不是只剩一个转圈。这里覆盖三条链路：快照持久化、同账号重登不清缓存、二级页首屏直出。
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  test('ToolCache 快照写入闪存，重启后 load 能读回', () async {
    ToolCache.score = ToolCache.scoreOf({'total': 8, 'credit': 5});
    ToolCache.electricity = ToolCache.electricityOf({'balance': 12.5});
    await Future<void>.delayed(Duration.zero); // 等落盘（setter 不阻塞 UI）

    final sp = await SharedPreferences.getInstance();
    expect(sp.getString('tool_cache_score'), contains('"total":8'));
    expect(sp.getString('tool_cache_electricity'), contains('12.5'));

    // 模拟进程重启：内存清空，再从闪存读回
    await ToolCache.clear();
    expect(ToolCache.score, isNull);
    await sp.setString('tool_cache_score', '{"total":9,"credit":6}');
    await sp.setString('tool_cache_electricity', '{"balance":3.5}');
    await ToolCache.load();
    expect(ToolCache.score?.total, 9);
    expect(ToolCache.electricity?.balance, 3.5);
  });

  test('token 续期 / 同账号重登不清工具页缓存，换账号才清', () async {
    AppState.I.username = 'u1';
    await ToolPageCache.write('activities', {
      'data': {
        'activities': [
          {'id': '1'}
        ]
      }
    });

    // 掉线自动重登 / 滑动续期：还是同一个账号
    await AppState.I.saveLogin(token: 't2', username: 'u1', password: 'p');
    expect(await ToolPageCache.read('activities'), isNotNull,
        reason: '同账号续期不能把上次的数据抹掉');

    // 换账号：必须清掉，别把上一个人的数据显示给下一个人
    await AppState.I.saveLogin(token: 't3', username: 'u2', password: 'p');
    expect(await ToolPageCache.read('activities'), isNull);
  });

  testWidgets('预取写入的分数缓存让二课分数页首屏直接显示，不转圈', (tester) async {
    AppState.I.autoRefreshTools = false;
    addTearDown(() => AppState.I.autoRefreshTools = true);
    final sp = await SharedPreferences.getInstance();
    // 达标线用本地缓存顶掉网络请求，避免测试等到超时
    await sp.setString('score_targets_v1', '{}');
    await sp.setInt('score_targets_v1_at', DateTime.now().millisecondsSinceEpoch);
    await ToolPageCache.write('score', {
      'data': {
        'student': {'xh': '25110001', 'xm': '张三'},
        'total': 8,
        'credit': 5,
        'groups': [],
      }
    });

    await tester.pumpWidget(const MaterialApp(home: ScorePage()));
    await tester.pump(); // 读缓存这一帧
    expect(find.byType(CircularProgressIndicator), findsNothing,
        reason: '有缓存就不该先转圈');
    await tester.pumpAndSettle();
    expect(find.textContaining('25110001'), findsOneWidget);
  });
}
