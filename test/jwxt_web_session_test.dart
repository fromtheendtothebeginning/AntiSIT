import 'package:campus_core/campus_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// 服务器模式评教页依赖的两块数据：服务器下发的教务会话 + 校园隧道代理地址（结构一变就是「打开是登录页」）。
void main() {
  group('服务器教务网页会话', () {
    test('解析 cookies / jwxt_base，Cookie 值统一成字符串', () {
      final s = JwxtWebSession.fromServer({
        'cookies': {'JSESSIONID': 'abc', 'route': 123},
        'jwxt_base': ' https://jwxt.sit.edu.cn ',
      });
      expect(s.cookies, {'JSESSIONID': 'abc', 'route': '123'});
      expect(s.base, 'https://jwxt.sit.edu.cn');
    });

    test('结构不对时返回空会话，不抛', () {
      expect(JwxtWebSession.fromServer(null).cookies, isEmpty);
      expect(JwxtWebSession.fromServer('x').base, isEmpty);
      expect(JwxtWebSession.fromServer({'cookies': []}).cookies, isEmpty);
      expect(
        JwxtWebSession.fromServer({
          'cookies': {'a': null},
        }).cookies,
        isEmpty,
      );
    });
  });

  group('校园隧道网页代理', () {
    test('已连接时拼出 http://host:port', () {
      expect(
        campusProxyFromStatus({
          'session': {
            'connected': true,
            'host': 'anticraft.top',
            'http_port': 10004,
          },
        }),
        'http://anticraft.top:10004',
      );
    });

    test('host 带 scheme / 尾部斜杠也能归一', () {
      expect(
        campusProxyFromStatus({
          'session': {
            'connected': true,
            'host': 'https://anticraft.top/',
            'http_port': 10004,
          },
        }),
        'http://anticraft.top:10004',
      );
    });

    test('未连接 / 缺端口 / 结构不对返回空串', () {
      expect(campusProxyFromStatus(null), '');
      expect(
        campusProxyFromStatus({
          'session': {'connected': false, 'host': 'a', 'http_port': 1},
        }),
        '',
      );
      expect(
        campusProxyFromStatus({
          'session': {'connected': true, 'host': 'a'},
        }),
        '',
      );
      expect(
        campusProxyFromStatus({
          'session': {'connected': true, 'host': '', 'http_port': 1},
        }),
        '',
      );
      expect(
        campusProxyFromStatus({
          'session': {'connected': true, 'host': '127.0.0.1', 'http_port': 10004},
        }),
        '',
      );
      expect(campusProxyFromStatus({'session': 'x'}), '');
    });
  });
}
