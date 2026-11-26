part of 'mock_campus_server.dart';

/// 教务登录页（未开启统一身份认证时用不带按钮的版本）。
const String _jwxtLoginPage = '''
<html><body>
<form id="loginForm" method="post" action="/jwglxt/xtgl/login_slogin.html">
  <input type="hidden" name="csrftoken" value="mock-csrf-token"/>
  <input type="text" name="yhm"/>
  <input type="password" name="mm"/>
  <input type="text" name="yzm"/>
  <img id="kaptchaImg" src="/jwglxt/kaptcha"/>
  <input type="submit" value="登录"/>
</form>
<a id="authLogin" href="/jwglxt/xtgl/login_ssologin.html">统一身份认证登录</a>
</body></html>''';

/// 未开启统一身份认证时，登录页上去掉那个按钮（客户端应回落到「账号密码登录失败」）。
const String _jwxtLoginPageNoSso = '''
<html><body>
<form id="loginForm" method="post" action="/jwglxt/xtgl/login_slogin.html">
  <input type="hidden" name="csrftoken" value="mock-csrf-token"/>
  <input type="text" name="yhm"/>
  <input type="password" name="mm"/>
  <input type="text" name="yzm"/>
  <img id="kaptchaImg" src="/jwglxt/kaptcha"/>
  <input type="submit" value="登录"/>
</form>
</body></html>''';

/// 选课首页：隐藏域给出学期与控制参数，queryCourse(...) 给出可选类别。
/// 两个类别的 xkkz_id / xkkz_xh 故意互不相同，用来测「两者独立、不能互相推导」。
const String _courseIndexPage = '''
<html><body>
<input type="hidden" name="xkxnm" value="2026"/>
<input type="hidden" name="xkxqm" value="12"/>
<input type="hidden" name="firstXkkzId" value="KZ1"/>
<input type="hidden" name="firstXkkzXh" value="XH1"/>
<script>
function queryCourse(kklxdm, xkkzId, njdmId, zyhId, xkkzXh) {}
queryCourse('1', 'KZ1', '2025', 'ZY1', 'XH1');
queryCourse('2', 'KZ2', '2025', 'ZY1', 'XH2');
</script>
</body></html>''';

/// 正方教务（含统一认证入口）的路由处理。
extension MockCampusJwxtRoutes on MockCampusServer {
  Future<void> _jwxt(
    HttpRequest req,
    HttpResponse res,
    _MockSession s,
    String path,
    Map<String, String> form,
  ) async {
    switch (path) {
      // 登录：GET 出登录页（含 csrftoken），POST 校验凭据
      case '/jwglxt/xtgl/login_slogin.html':
        if (req.method == 'POST') {
          final yzm = (form['yzm'] ?? '').toUpperCase();
          if (yzm.isEmpty || yzm != (s.jwxtCaptcha ?? '').toUpperCase()) {
            return _jwxtLoginFail(res, '验证码错误');
          }
          if ((form['yhm'] ?? '') != MockCampusServer.studentId) return _jwxtLoginFail(res, '用户名或密码错误');
          if (debugJwxtPasswordLoginRejected ||
              _rsaDecrypt(form['mm'] ?? '') != MockCampusServer.password) {
            return _jwxtLoginFail(res, '用户名或密码错误');
          }
          s.jwxt = true;
          s.jwxtCaptcha = null;
          return _redirect(res, '/jwglxt/xtgl/index_initMenu.html');
        }
        return _html(res, _loginPageHtml);

      case '/jwglxt/xtgl/login_getPublicKey.html':
        return _json(res, {'modulus': _rsaModulusB64, 'exponent': _rsaExponentB64});

      case '/jwglxt/kaptcha':
        s.jwxtCaptcha = randomCaptchaCode();
        debugJwxtCaptcha = s.jwxtCaptcha;
        debugPrint('[mock] 教务验证码 = ${s.jwxtCaptcha}');
        return _png(res, renderCaptchaPng(s.jwxtCaptcha!));

      // 会话探活：未登录返回 302（客户端 checkSession → false）
      case '/jwglxt/xtgl/index_initMenu.html':
        if (!s.jwxt) return _redirect(res, '/jwglxt/xtgl/login_slogin.html');
        return _html(res, '<html><body><div id="mock">index_initMenu</div></body></html>');

      // 统一认证入口：未带票据 → 302 去 authserver；带 ticket 回来 → 建立教务会话
      case '/jwglxt/xtgl/login_ssologin.html':
        if (debugJwxtNoSsoEntry) {
          return _text(res, 404, 'mock: 未开启统一身份认证', 'text/plain; charset=utf-8');
        }
        if ((req.uri.queryParameters['ticket'] ?? '').isNotEmpty && s.cas) {
          s.jwxt = true;
          return _redirect(res, '/jwglxt/xtgl/index_initMenu.html');
        }
        final service = '$baseUrl/jwglxt/xtgl/login_ssologin.html';
        return _redirect(
            res, '$baseUrl/authserver/login?service=${Uri.encodeComponent(service)}');

      case '/jwglxt/cjcx/cjcx_cxXsgrcj.html':
        if (!s.jwxt) return _jwxtExpired(res);
        final xnm = form['xnm'] ?? '';
        final xqm = form['xqm'] ?? '';
        final all = (debugGrades ?? _grades)
            .where((g) => (xnm.isEmpty || g['xnm'] == xnm) && (xqm.isEmpty || g['xqm'] == xqm))
            .toList();
        // 真实正方按 queryModel.showCount/currentPage 分页，totalResult 给总条数：
        // 客户端只取第 1 页就会漏掉后面的学期，这里必须照做才能测出这种漏。
        final size = int.tryParse(form['queryModel.showCount'] ?? '') ?? 15;
        final page = int.tryParse(form['queryModel.currentPage'] ?? '') ?? 1;
        final from = (page - 1) * size;
        final items = from >= all.length ? const [] : all.skip(from).take(size).toList();
        return _json(res, {'items': items, 'totalResult': '${all.length}'});

      case '/jwglxt/kbcx/xskbcxMobile_cxXsKb.html':
        if (!s.jwxt) return _jwxtExpired(res);
        final zs = int.tryParse(form['zs'] ?? '') ?? 1;
        if (zs < 1 || zs > _mockWeekCount) {
          return _json(res, {'kbList': const [], 'rqazcList': const []});
        }
        return _json(res, {
          'kbList': [
            for (final c in _courses)
              if (zs >= (c['from'] as int) && zs <= (c['to'] as int))
                {
                  'kcmc': c['name'],
                  'cdmc': c['place'],
                  'xm': c['teacher'],
                  'kcb_id': c['code'],
                  'jxbmc': c['clazz'],
                  'xqj': '${(c['day'] as int) + 1}',
                  'jcs': c['slots'],
                },
          ],
          'rqazcList': _weekDates(zs),
          'xsxx': {'XNMC': '2026-2027学年', 'NJDM_ID': '2026'},
        });

      case '/jwglxt/kwgl/kscx_cxXsksxxIndex.html':
        if (!s.jwxt) return _jwxtExpired(res);
        return _json(res, {'items': _exams});

      // 学业情况：首页由服务端渲染 HTML（整体统计 + 各节点学分要求 + showKc 占位），
      // 某个节点的课程再由前端 POST xfyqjd_id 换 JSON 数组——照真实协议分两步。
      case '/jwglxt/xsxy/xsxyqk_cxXsxyqkIndex.html':
        if (!s.jwxt) return _jwxtExpired(res);
        return _html(res, debugAcademicIndexHtml ?? _academicIndexPage);

      case '/jwglxt/xsxy/xsxyqk_cxJxzxjhxfyqKcxx.html':
        if (!s.jwxt) return _jwxtExpired(res);
        debugLastAcademicForm = Map<String, String>.from(form);
        debugAcademicRequestLog.add('plan:${form['xfyqjd_id'] ?? ''}');
        final rawBody = debugAcademicCoursesBody;
        if (rawBody != null) {
          return _text(res, 200, rawBody, 'text/html; charset=utf-8');
        }
        final id = form['xfyqjd_id'] ?? '';
        // debug 覆盖按节点合并（只覆盖指定 id，其余仍用内置样例），方便单点造变体。
        final override = debugAcademicCourses;
        final data = (override != null && override.containsKey(id))
            ? override[id]!
            : _academicCourses[id] ?? const [];
        return _json(res, data);

      // 非课程信息节点（页面 loadKc() 里 jdkcsx != '1' 的分支）：
      // 通识类 / 实践环节等的明细在这里，接口与教学计划分开。
      case '/jwglxt/xsxy/xsxyqk_cxJxzxjhxfyqFKcxx.html':
        if (!s.jwxt) return _jwxtExpired(res);
        final nonCourseId = form['xfyqjd_id'] ?? '';
        debugAcademicRequestLog.add('noncourse:$nonCourseId');
        return _json(
          res,
          (debugAcademicNonCourses ?? _academicNonCourses)[nonCourseId] ?? const [],
        );

      // 首页：选课轮次参数藏在隐藏域里，类别由 queryCourse(...) 声明。
      case '/jwglxt/xsxk/zzxkyzb_cxZzxkYzbIndex.html':
        if (!s.jwxt) return _jwxtExpired(res);
        return _html(res, _courseIndexPage);

      // 展示页：返回该类别最新的 xkkz_id / xkkz_xh（两者独立，不能互相推导）。
      case '/jwglxt/xsxk/zzxkyzb_cxZzxkYzbDisplay.html':
        if (!s.jwxt) return _jwxtExpired(res);
        final displayCategory = form['kklxdm'] ?? '1';
        final displayControl = displayCategory == '2'
            ? const ['KZ2', 'XH2', '通识选课']
            : const ['KZ1', 'XH1', '主修选课'];
        return _html(res, '''
<html><body>
<input type="hidden" name="xkkz_id" value="${displayControl[0]}"/>
<input type="hidden" name="xkkz_xh" value="${displayControl[1]}"/>
<input type="hidden" name="kklxmc" value="${displayControl[2]}"/>
</body></html>''');

      // 课程列表：kspage/jspage 是 1 基记录号（不是页码），filter_list[0] 是关键词。
      case '/jwglxt/xsxk/zzxkyzb_cxZzxkYzbPartDisplay.html':
        if (!s.jwxt) return _jwxtExpired(res);
        final listCategory = form['kklxdm'] ?? '1';
        final keyword = (form['filter_list[0]'] ?? '').trim();
        final offers = <Map<String, Object?>>[
          if (listCategory == '1') ...[
            {
              'kch_id': 'K001',
              'kcmc': '高等数学',
              'jsxm': '李老师',
              'sksj': '周一 1-2节',
              'jxdd': 'A101',
              'xf': '4.0',
              'jxbrl': '60',
              'yxzrs': '60',
            },
            {
              'kch_id': 'K002',
              'kcmc': '大学英语',
              'jsxm': '王老师',
              'sksj': '周三 3-4节',
              'jxdd': 'B202',
              'xf': '3.0',
              'jxbrl': '40',
              'yxzrs': '12',
            },
          ] else if (listCategory == '2') ...[
            {
              'kch_id': 'K003',
              'kcmc': '中国近现代史纲要',
              'jsxm': '赵老师',
              'sksj': '周五 5-6节',
              'jxdd': 'C303',
              'xf': '2.0',
              'jxbrl': '80',
              'yxzrs': '3',
            },
          ],
        ]
            .where((c) =>
                keyword.isEmpty || '${c['kcmc']}'.contains(keyword))
            .toList();
        final from = ((int.tryParse(form['kspage'] ?? '') ?? 1) - 1).clamp(0, offers.length);
        final to = (int.tryParse(form['jspage'] ?? '') ?? offers.length)
            .clamp(from, offers.length);
        return _json(res, {'tmpList': offers.sublist(from, to)});

      // 教学班：jxb_id 与提交用的 do_jxb_id 可以不同，客户端应优先用后者。
      case '/jwglxt/xsxk/zzxkyzbjk_cxJxbWithKchZzxkYzb.html':
        if (!s.jwxt) return _jwxtExpired(res);
        final sectionCourse = form['kch_id'] ?? '';
        final sections = <Map<String, Object?>>[
          if (sectionCourse == 'K001') ...[
            {
              'jxb_id': 'JXB1',
              'do_jxb_id': 'TOKEN1',
              'jxbmc': '高等数学01班',
              'jsxm': '李老师',
              'sksj': '周一 1-2节',
              'jxdd': 'A101',
              'jxbrl': '60',
              'yxzrs': '60',
            },
            {
              'jxb_id': 'JXB2',
              'do_jxb_id': 'TOKEN2',
              'jxbmc': '高等数学02班',
              'jsxm': '李老师',
              'sksj': '周二 3-4节',
              'jxdd': 'A102',
              'jxbrl': '60',
              'yxzrs': '59',
            },
          ] else if (sectionCourse == 'K002') ...[
            {
              'jxb_id': 'JXB3',
              'do_jxb_id': 'TOKEN3',
              'jxbmc': '大学英语01班',
              'jsxm': '王老师',
              'sksj': '周三 3-4节',
              'jxdd': 'B202',
              'jxbrl': '40',
              'yxzrs': '12',
            },
          ] else if (sectionCourse == 'K003') ...[
            {
              'jxb_id': 'JXB4',
              'do_jxb_id': 'TOKEN4',
              'jxbmc': '近现代史01班',
              'jsxm': '赵老师',
              'sksj': '周五 5-6节',
              'jxdd': 'C303',
              'jxbrl': '80',
              'yxzrs': '3',
            },
          ],
        ];
        return _json(res, {'tmpList': sections});

      // 选课提交：正常返回纯文本 1；名额满返回 flag=-1 + "已报人数,jxb_id,剩余,"。
      case '/jwglxt/xsxk/zzxkyzbjk_xkBcZyZzxkYzb.html':
        if (!s.jwxt) return _jwxtExpired(res);
        debugLastSelectForm = Map<String, String>.from(form);
        if (debugSelectFailures > 0) {
          debugSelectFailures--;
          return _json(res, {'flag': '-1', 'msg': '60,TOKEN2,0,'});
        }
        final jxb = form['jxb_ids'] ?? '';
        if (_selectedCourses.any((c) => c['jxb_id'] == jxb)) {
          return _json(res, {'flag': '-1', 'msg': '已选该教学班'});
        }
        _selectedCourses.add({
          'jxb_id': jxb,
          'do_jxb_id': jxb,
          'kch_id': form['kch_id'] ?? '',
          'kcmc': form['kcmc'] ?? '',
        });
        return _text(res, 200, '1', 'text/plain; charset=utf-8');

      case '/jwglxt/xsxk/zzxkyzb_cxZzxkYzbChoosedDisplay.html':
        if (!s.jwxt) return _jwxtExpired(res);
        return _json(res, {'tmpList': _selectedCourses});
    }
    _text(res, 404, 'mock: 未实现的教务路径 $path', 'text/plain; charset=utf-8');
  }

  String get _loginPageHtml => debugJwxtNoSsoEntry ? _jwxtLoginPageNoSso : _jwxtLoginPage;

  void _tips(HttpResponse res, String msg) =>
      _html(res, '<html><body><div id="tips">$msg</div></body></html>');

  /// 教务登录失败页：默认 #tips 文案；测试用 debugJwxtLoginFailBody 换成没有可读文案的页面。
  void _jwxtLoginFail(HttpResponse res, String msg) {
    final body = debugJwxtLoginFailBody;
    if (body == null) return _tips(res, msg);
    _html(res, body);
  }

  /// 会话过期时业务接口的应答：真实正方有些版本不打回 302，而是直接给一张登录页 HTML
  /// （客户端若把它当成 JSON 解析就会失败，还容易误报成「这周没课」）。
  void _jwxtExpired(HttpResponse res) => _html(res, _loginPageHtml);

  /// 测试用：服务端偷偷把教务会话删掉（模拟正方会话超时），客户端并不知情。
  void debugForgetJwxtSession() {
    for (final s in _sessions.values) {
      s.jwxt = false;
    }
  }
}
