import 'dart:convert';
import 'dart:io';

import 'package:campus_core/campus_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 二课扫码签到的**双模式路由**验收：直连走 CampusDirect（有独立单测），
/// 服务器模式必须打到 `/api/campus-open/activities/sign`（签到 / 签退）与
/// `/api/campus-open/activities/train-sign`（报名 / 培训码），参数原样透传。
/// 用真 HTTP 打本地假服务——必须是普通 test（widget 测试的假 HttpClient 会拦成 400），
/// 且放在独立文件里，避免同文件前面的 widget 测试把 ApiClient 的客户端困在 FakeAsync。
void main() {
  late HttpServer server;
  String? path;
  Map<String, dynamic>? body;

  setUp(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    await AppState.I.load();
    AppState.I.demo = false;
    AppState.I.mode = AppMode.server;
    AppState.I.token = 'test-token';

    path = null;
    body = null;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    AppState.I.serverUrl = 'http://127.0.0.1:${server.port}';
    server.listen((req) async {
      path = req.uri.path;
      body = jsonDecode(await utf8.decoder.bind(req).single);
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode({'ok': true, 'data': {'msg': '签到成功'}}));
      await req.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    AppState.I.demo = false;
    AppState.I.mode = AppMode.direct;
  });

  test('签到 / 签退码：POST /activities/sign，hdId + hdActId 透传', () async {
    final r = await ApiClient.I.activitySignInOrSignOut(
        '94b69a40f38eedd060cf9ecec1fe78cd', 'c4f2a32a171df39ee5ba8834c8a425ee');
    expect(path, '/api/campus-open/activities/sign');
    expect(body, {
      'hdId': '94b69a40f38eedd060cf9ecec1fe78cd',
      'hdActId': 'c4f2a32a171df39ee5ba8834c8a425ee',
    });
    expect(r['data']['msg'], '签到成功');
  });

  test('报名（培训）码：POST /activities/train-sign，hdId + pxId 透传', () async {
    final r = await ApiClient.I.activityTrainingSignIn(
        'ee49d370b72dceef4c7b5a6d3580ebfc', 'a50571f3af113b02945b5309fe815f93');
    expect(path, '/api/campus-open/activities/train-sign');
    expect(body, {
      'hdId': 'ee49d370b72dceef4c7b5a6d3580ebfc',
      'pxId': 'a50571f3af113b02945b5309fe815f93',
    });
    expect(r['data']['msg'], '签到成功');
  });
}
