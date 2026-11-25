part of 'mock_campus_server.dart';

/// SIT 真实 CAS 登录页的静态错误骨架（隐藏元素，仅 JS 改写用）。
const String _mockCasErrorSkeleton = '''
<span id="usernameError" style="display:none;" class="auth_error">请输入用户名</span>
<span id="usernameSpecificError" style="display:none;" class="auth_error"></span>
<span id="passwordError" style="display:none;" class="auth_error">请输入密码</span>
<span id="cpatchaError" style="display:none;" class="auth_error">请输入验证码</span>''';

/// 统一身份认证（CAS）与学工系统的路由处理。
extension MockCampusIdentityRoutes on MockCampusServer {
  Future<void> _cas(
    HttpRequest req,
    HttpResponse res,
    _MockSession s,
    String path,
    Map<String, String> form,
  ) async {
    switch (path) {
      case '/authserver/login':
        if (req.method == 'POST') {
          final cap = (form['captchaResponse'] ?? '').toUpperCase();
          if (cap.isEmpty || cap != (s.authCaptcha ?? '').toUpperCase()) {
            return _casError(res, 'cpatchaError', '验证码错误');
          }
          if ((form['username'] ?? '') != MockCampusServer.studentId) {
            return _casError(res, 'usernameError', '用户名或密码错误');
          }
          if (!_wiseduPasswordOk(form['password'] ?? '', s.casSalt, MockCampusServer.password)) {
            return _casError(res, 'passwordError', '用户名或密码错误');
          }
          s.cas = true; // 统一认证会话（CASTGC）建立
          s.authCaptcha = null;
          return _redirect(res, _ticketUrl(s.casService));
        }
        s.casService = req.uri.queryParameters['service'] ?? s.casService;
        // 统一认证会话还有效时不渲染登录页，直接带票据 302 回业务系统（真实 CAS 的 SSO 行为）
        if (s.cas) return _redirect(res, _ticketUrl(s.casService));
        s.casExecution = 'e1s1-mock-${DateTime.now().microsecondsSinceEpoch}';
        s.casLt = 'LT-mock-${DateTime.now().microsecondsSinceEpoch}';
        s.casSalt = _randomSalt();
        return _html(res, _casLoginPage(s));

      case '/authserver/captcha.html':
        s.authCaptcha = randomCaptchaCode();
        debugAuthCaptcha = s.authCaptcha;
        debugPrint('[mock] 统一认证验证码 = ${s.authCaptcha}');
        return _png(res, renderCaptchaPng(s.authCaptcha!));
    }
    _text(res, 404, 'mock: 未实现的认证路径 $path', 'text/plain; charset=utf-8');
  }

  String _casLoginPage(_MockSession s) {
    final saltInput = debugFlipSaltAttribute
        ? '<input type="hidden" value="${s.casSalt}" id="pwdDefaultEncryptSalt"/>'
        : '<input type="hidden" id="pwdDefaultEncryptSalt" value="${s.casSalt}"/>';
    return '''
<html><body>
$_mockCasErrorSkeleton
<form id="casLoginForm" method="post" action="/authserver/login">
  <input type="hidden" name="execution" value="${s.casExecution}"/>
  <input type="hidden" name="_eventId" value="submit"/>
  <input type="hidden" name="lt" value="${s.casLt}"/>
  <input type="hidden" name="rmShown" value="1"/>
  <input type="hidden" name="dllt" value="userNamePasswordLogin"/>
  $saltInput
  <input type="text" id="username" name="username" placeholder="学号"/>
  <input type="password" id="password" name="password"/>
  <input type="text" id="captchaResponse" name="captchaResponse"/>
  <img id="captchaImg" src="/authserver/captcha.html"/>
  <button type="submit" class="auth_login_btn">登录</button>
</form>
</body></html>''';
  }

  /// 登录失败页：按 SIT 真实页面形态返回——静态骨架原样保留（含隐藏的 error 元素），
  /// 服务端判定结果渲染在可见的 `#msg`。客户端读的是可见元素，隐藏骨架不该被当成错误原因。
  void _casError(HttpResponse res, String elementId, String msg) => _html(
      res,
      '<html><body>$_mockCasErrorSkeleton'
      '<span id="msg" class="auth_error" style="top:-19px;">$msg</span>'
      '</body></html>');

  Future<void> _xg(
    HttpRequest req,
    HttpResponse res,
    _MockSession s,
    String path,
    Map<String, String> form,
  ) async {
    switch (path) {
      // 业务系统入口：没有业务会话就 302 去统一认证；带 ticket 回来则建立业务会话
      case '/zftal-xgxt-web/teacher/xtgl/index/check.zf':
        if ((req.uri.queryParameters['ticket'] ?? '').isNotEmpty && s.cas) s.xg = true;
        if (!s.xg) return _redirect(res, _casLoginUrl(path));
        return _html(res, '<html><body>xgHome ok</body></html>');

      case '/zftal-xgxt-web/teacher/xtgl/login/getCurrentUser.zf':
        return _json(res, s.xg
            ? {
                'code': 0,
                'msg': 'ok',
                'data': {'xh': MockCampusServer.studentId, 'xm': MockCampusServer.realName},
              }
            : {'code': 1, 'msg': '未登录'});

      case '/zftal-xgxt-web/xsrdtjcx/getAllXslbTjcx.zf':
        if (!s.xg) return _redirect(res, _casLoginUrl(path));
        return _json(res, {
          'code': 0,
          'tableHeader': _scoreHeader,
          'queryModel': {
            'items': [_scoreItem],
          },
        });

      case '/zftal-xgxt-web/hdgl/getHdgcHdList.zf':
        if (!s.xg) return _redirect(res, _casLoginUrl(path));
        return _json(res, {
          'code': 0,
          'data': {
            'resultList': [
              {
                'dlmc': '思想成长',
                'lblist': [
                  {'lbmc': '讲座报告', 'hdlist': [_activityItems['m001']]},
                  {'lbmc': '实践活动', 'hdlist': [_activityItems['m003']]},
                ],
              },
              {
                'dlmc': '社会实践',
                'lblist': [
                  {'lbmc': '志愿服务', 'hdlist': [_activityItems['m002']]},
                ],
              },
            ],
          },
        });

      // （2026-11 起真实接口 hdgl/list.zf 被确认为匿名公共池，「我的报名」已改走下方 bizFlow；此 case 保留作协议兼容。）
      case '/zftal-xgxt-web/hdgl/list.zf':
        if (!s.xg) return _redirect(res, _casLoginUrl(path));
        final signedOnly = (form['all'] ?? '1') == '0';
        final items = [
          {
            'id': 'm001', 'hdmc': 'AI 赋能学习效率提升讲座',
            'dldm': '01', 'dlmc': '思想成长', 'lbdm': '0101', 'lbmc': '讲座报告',
            'hdkssj': '2026-10-10 14:00:00', 'hdjssj': '2026-10-10 16:00:00',
            'hddd': '线下', 'hdbmzt': '5', 'bm': signedOnly ? 1 : 0,
          },
          {
            'id': 'm002', 'hdmc': '秋季校园马拉松志愿者',
            'dldm': '02', 'dlmc': '劳育', 'lbdm': '0201', 'lbmc': '志愿公益',
            'hdkssj': '2026-10-18 07:00:00', 'hdjssj': '2026-10-18 13:00:00',
            'hddd': '线下', 'hdbmzt': '6', 'bm': signedOnly ? 1 : 0,
          },
          if (!signedOnly)
            {
              'id': 'm003', 'hdmc': '实验室开放日参观',
              'dldm': '03', 'dlmc': '美育', 'lbdm': '0301', 'lbmc': '校园文化活动',
              'hdkssj': '2026-09-20 13:30:00', 'hdjssj': '2026-09-20 17:00:00',
              'hddd': '线下', 'hdbmzt': '6', 'bm': 0,
            },
        ];
        return _json(res, {
          'code': 0,
          'msg': '操作成功',
          'data': {'items': items, 'totalCount': items.length, 'pageNo': 0, 'pageSize': 15},
        });

      // bizFlow 结果组：groupCode=xshd = 报名结果（我的报名）；xsrd = 学分认定（加分明细，学分在 rdxs）。
      case '/zftal-xgxt-web/bizFlow/result/group/list.zf':
        if (!s.xg) return _redirect(res, _casLoginUrl(path));
        if ((form['groupCode'] ?? '') == 'xsrd') {
          return _json(res, {
            'code': 0,
            'msg': '操作成功',
            'data': {
              'bizName': '学分认定',
              'formCode': 'xsrd',
              'formName': '学分认定',
              'totalCount': 2,
              'rows': [
                {
                  'INSTANCE_ID': 'inst-1',
                  'hdmc': 'AI 赋能学习效率提升讲座',
                  'dldm': '美育', 'lbdm': '校园文化活动',
                  'rdxs': '0.20',
                  'flowstatusmc': '通过', 'FLOWSTATUS': 'finish',
                  'CREATE_TIME': '2026-10-11 09:00:00',
                },
                {
                  'INSTANCE_ID': 'inst-2',
                  'hdmc': '秋季校园马拉松志愿者',
                  'dldm': '劳育', 'lbdm': '志愿公益',
                  'rdxs': '0.50',
                  'flowstatusmc': '通过', 'FLOWSTATUS': 'finish',
                  'CREATE_TIME': '2026-10-19 10:00:00',
                },
              ],
            },
          });
        }
        return _json(res, {
          'code': 0,
          'msg': '操作成功',
          'data': {
            'bizName': '学生活动申请',
            'formCode': 'hdsq',
            'formName': '学生活动申请',
            'totalCount': 2,
            'rows': [
              {
                'INSTANCE_ID': 'inst-1',
                'hdid': 'm001',
                'hdmc': 'AI 赋能学习效率提升讲座',
                'dldm': '德育', 'lbdm': '讲座报告',
                'flowstatusmc': '通过', 'FLOWSTATUS': 'finish',
                'hdkssj': '2026-10-10 14:00:00', 'hdjssj': '2026-10-10 16:00:00',
                'CREATE_TIME': '2026-10-11 09:00:00',
              },
              {
                'INSTANCE_ID': 'inst-2',
                'hdid': 'm002',
                'hdmc': '秋季校园马拉松志愿者',
                'dldm': '劳育', 'lbdm': '志愿公益',
                'flowstatusmc': '通过', 'FLOWSTATUS': 'finish',
                'hdkssj': '2026-10-18 07:00:00', 'hdjssj': '2026-10-18 13:00:00',
                'CREATE_TIME': '2026-10-19 10:00:00',
              },
            ],
          },
        });

      case '/zftal-xgxt-web/hdgl/details.zf':
        if (!s.xg) return _redirect(res, _casLoginUrl(path));
        final id = req.uri.queryParameters['id'] ?? '';
        final a = _activityItems[id];
        if (a == null) return _json(res, {'code': 1, 'msg': '活动不存在'});
        return _json(res, {
          'code': 0,
          'data': {
            'id': a['id'],
            'hdmc': a['hdmc'],
            'hdms': a['hdms'],
            // 学校实测 bm 是 int/str 两态：mock 直接给 int 1/0，覆盖归一比较
            'bm': s.signedUpActivities.contains(id) ? 1 : 0,
          },
        });

      // 活动报名（学工工作流 hdsq）：先取动态表单定义（预填值全部由学校生成），
      // 再 urlencoded 平铺提交，成功返回工作流实例 ID——与真实系统同款协议。
      case '/zftal-xgxt-web/dynamic/form/find/hdsq/default.zf':
        if (!s.xg) return _redirect(res, _casLoginUrl(path));
        final dataId = req.uri.queryParameters['dataId'] ?? '';
        final aid = dataId.split('|').last;
        if (!_activityItems.containsKey(aid)) {
          return _json(res, {'code': 1, 'msg': '活动不存在'});
        }
        return _json(res, {
          'code': 0,
          'data': {
            'saveUrl': '/hdgl/flow/apply/hdsq.zf',
            'fields': [
              {'fieldCode': 'hdid', 'defaultValue': aid},
              {'fieldCode': 'xh', 'defaultValue': MockCampusServer.studentId},
              {'fieldCode': 'xm', 'defaultValue': MockCampusServer.realName},
              {'fieldCode': 'xb', 'defaultValue': '男'},
              {'fieldCode': 'csrq', 'defaultValue': '2006-01-01'},
              {'fieldCode': 'zzmm', 'defaultValue': '共青团员'},
              {'fieldCode': 'mz', 'defaultValue': '汉族'},
              {'fieldCode': 'sjh', 'defaultValue': '13800000000'},
              {'fieldCode': 'zjhm', 'defaultValue': '310101200601010011'},
              {'fieldCode': 'bmmc', 'defaultValue': '计算机学院'},
              {'fieldCode': 'zymc', 'defaultValue': '计算机科学与技术'},
              {'fieldCode': 'bjmc', 'defaultValue': '计科2501'},
              {'fieldCode': 'nj', 'defaultValue': '2025'},
              {'fieldCode': 'xnxq', 'defaultValue': '2025-2026-1'},
              {'fieldCode': 'hdkssj|hdjssj', 'defaultValue': '2026-10-10 14:00:00,2026-10-10 16:00:00'},
              {'fieldCode': 'dqxf', 'defaultValue': '5.5'},
              {'fieldCode': 'ljxf', 'defaultValue': '5.5'},
              {'fieldCode': 'bmfj', 'defaultValue': null}, // 附件字段：客户端应跳过
              {'fieldCode': 'grjs', 'defaultValue': ''},
              {'fieldCode': 'grgzjl', 'defaultValue': ''},
              {'fieldCode': 'hjry', 'defaultValue': ''},
              {'fieldCode': 'bmyy', 'defaultValue': ''},
              {'fieldCode': 'zyjn', 'defaultValue': ''},
            ],
          },
        });

      case '/zftal-xgxt-web/hdgl/flow/apply/hdsq.zf':
        if (!s.xg) return _redirect(res, _casLoginUrl(path));
        debugLastSignupForm = form;
        final aid = form['hdid'] ?? '';
        if (aid.isEmpty || form['xh'] != MockCampusServer.studentId || (form['hdkssj'] ?? '').isEmpty) {
          return _json(res, {'code': 1, 'msg': '报名表单校验失败'});
        }
        if (s.signedUpActivities.contains(aid)) {
          return _json(res, {'code': 1, 'msg': '该活动已报名，请勿重复报名'});
        }
        s.signedUpActivities.add(aid);
        return _json(res, {
          'code': 0,
          'data': {'instanceId': 'inst-${DateTime.now().millisecondsSinceEpoch}'},
        });
    }
    _text(res, 404, 'mock: 未实现的学工路径 $path', 'text/plain; charset=utf-8');
  }

  String _casLoginUrl(String servicePath) =>
      '$baseUrl/authserver/login?service=${Uri.encodeComponent('$baseUrl$servicePath')}';

  /// 统一认证回业务系统的跳转：真实 CAS 一定带 ticket（业务系统据此建会话）。
  String _ticketUrl(String service) {
    final target =
        service.isEmpty ? '$baseUrl/zftal-xgxt-web/teacher/xtgl/index/check.zf' : service;
    final sep = target.contains('?') ? '&' : '?';
    return '$target${sep}ticket=ST-mock-${DateTime.now().microsecondsSinceEpoch}';
  }

  /// 测试用：只丢业务会话、保留统一认证会话（模拟 CASTGC 有效但学工 Cookie 过期）。
  void debugForgetXgSession() {
    for (final s in _sessions.values) {
      s.xg = false;
    }
  }
}
