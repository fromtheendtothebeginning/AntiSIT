/// 直连模式的「测试连接」探测：逐项请求教务 / 学工 / 校园卡并返回可达性。
library;

import '../api_error.dart';
import '../app_state.dart';
import 'epay.dart';
import 'jwxt.dart';
import 'xg.dart';

/// 探测结果（连接设置页「测试连接」逐项展示）。
typedef ProbeResult = ({String name, bool ok, String detail});

/// 逐项探测学校系统可达性（教务 / 学工 / 校付宝），失败写进结果而不抛异常。
Future<List<ProbeResult>> testDirectConnection() async {
  final s = AppState.I.school;
  final out = <ProbeResult>[];
  out.add(await _probe('教务系统', () async {
    final c = JwxtClient(s.jwxtBase,
        aesKey: s.dektAesKey, allowSelfSigned: s.allowSelfSigned);
    try {
      final r = await c.probe();
      return r;
    } finally {
      c.dispose();
    }
  }));
  out.add(await _probe('学工系统', () async {
    final c = XgClient(
      authBase: s.authBase,
      xgBase: s.xgBase,
      allowSelfSigned: s.allowSelfSigned,
    );
    try {
      final r = await c.probe();
      return r;
    } finally {
      c.dispose();
    }
  }));
  out.add(await _probe('校园卡', () async {
    final c = EpayClient(s.ecardBase, allowSelfSigned: s.allowSelfSigned);
    try {
      return await c.probe();
    } finally {
      c.dispose();
    }
  }));
  return out;
}

Future<ProbeResult> _probe(String name, Future<String?> Function() run) async {
  try {
    final detail = await run();
    return (name: name, ok: true, detail: detail ?? '可达');
  } on ApiError catch (e) {
    return (name: name, ok: false, detail: e.message);
  } catch (e) {
    return (name: name, ok: false, detail: '$e');
  }
}
