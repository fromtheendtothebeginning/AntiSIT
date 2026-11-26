part of 'mock_campus_server.dart';

/// 校付宝（校园码 / 电费）的路由处理。
extension MockCampusEpayRoutes on MockCampusServer {
  Future<void> _epay(
    HttpRequest req,
    HttpResponse res,
    _MockSession s,
    String path,
    Map<String, dynamic> json,
  ) async {
    if (path == '/openservice/epeortalAuth/login') {
      if ('${json['custname']}' != MockCampusServer.realName ||
          '${json['stuempno']}' != MockCampusServer.studentId) {
        return _json(res, {'retcode': '-1', 'retmsg': '姓名或学号有误'});
      }
      String pwd;
      try {
        pwd = sm4Decrypt('${json['pwd']}');
      } catch (_) {
        return _json(res, {'retcode': '-2', 'retmsg': '支付密码解密失败'});
      }
      if (pwd != MockCampusServer.payPassword) return _json(res, {'retcode': '-1', 'retmsg': '支付密码错误'});
      s.epayToken = 'mock-token-${DateTime.now().microsecondsSinceEpoch}';
      return _json(res, {
        'retcode': '0',
        'retmsg': '登录成功',
        'data': {'token': s.epayToken},
      });
    }

    // 其余 openservice 接口都要 Bearer token；过期回 403（客户端会重登续期后重试）
    final auth = req.headers.value('sw-Authorization') ?? '';
    final token = auth.startsWith('Bearer ') ? auth.substring(7) : '';
    if (s.epayToken == null || token != s.epayToken) {
      return _json(res, {'retcode': '-3', 'retmsg': '登录已过期'}, status: 403);
    }

    switch (path) {
      case '/openservice/miniprogram/wxlayout':
        return _json(res, {
          'retcode': '0',
          'data': {
            'layout': {
              'balancePart': {
                'content': [
                  {'number': s.cardBalance.toStringAsFixed(2)},
                ],
              },
            },
          },
        });

      case '/openservice/miniprogram/queryroominfo':
        final buildid = '${json['buildid']}';
        final roomid = '${json['roomid']}';
        if (buildid != '${_dormBuilding + 1}' || roomid != '$_dormRoom') {
          return _json(res, {
            'retcode': '-1',
            'retmsg': '该寝室不存在（mock 只登记 ${MockCampusServer.dorm}）',
          });
        }
        return _json(res, {
          'retcode': '0',
          'data': {
            'restElecDegree': s.eleBalance.toStringAsFixed(2),
            'roomName': _draftDormName,
          },
        });

      case '/openservice/miniprogram/buyelectrityinit':
        s.pendingBillno = 'MOCK${DateTime.now().millisecondsSinceEpoch}';
        s.pendingAmount = (json['amount'] as num?)?.toDouble() ?? 0;
        return _json(res, {
          'retcode': '0',
          'data': {'billno': s.pendingBillno},
        });

      case '/openservice/miniprogram/balancepay':
        if (s.pendingBillno == null || '${json['billno']}' != s.pendingBillno) {
          return _json(res, {'retcode': '-1', 'retmsg': '订单号不匹配'});
        }
        final amount = s.pendingAmount;
        s.pendingBillno = null;
        s.pendingAmount = 0;
        s.eleBalance += amount / 100;
        s.cardBalance -= amount / 100;
        return _json(res, {
          'retcode': '0',
          'data': {
            'balance': (s.cardBalance * 100).round(), // 客户端按「分」解读
            'retmsg': '充值成功（mock）',
          },
        });

      case '/openservice/miniprogram/offline':
        return _json(res, {
          'retcode': '0',
          'data': {
            'qrcode': 'MOCK|${MockCampusServer.studentId}|${DateTime.now().millisecondsSinceEpoch ~/ 1000}',
          },
        });
    }
    _text(res, 404, 'mock: 未实现的校园卡路径 $path', 'text/plain; charset=utf-8');
  }
}
