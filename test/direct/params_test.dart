import 'package:campus_core/campus_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('寝室解析（校付宝 buildid = 楼号 + 1）', () {
    test('常见写法', () {
      for (final s in ['24号楼1016', '24-1016', '奉贤校区 24 号楼 1016']) {
        final d = parseDorm(s);
        expect(d.building, 24, reason: s);
        expect(d.room, 1016, reason: s);
        expect(d.buildid, 25, reason: s);
        expect(d.roomid, 1016, reason: s);
      }
    });

    test('解析不了时明确报错', () {
      expect(() => parseDorm('东侧宿舍'), throwsA(isA<Exception>()));
    });
  });

  group('教务字段解析', () {
    test('课程代码跳过 32 位 GUID 内部 ID', () {
      const guid = 'A1B2C3D4E5F60718293A4B5C6D7E8F90';
      expect(readableCourseCode([guid, 'CS101']), 'CS101');
      expect(readableCourseCode([null, '  ', 'kch-1']), 'kch-1');
      expect(readableCourseCode([guid, null]), '');
    });
  });

  group('活动说明解析', () {
    test('名额提取与「不限」识别', () {
      expect(extractQuota('本次活动招募人数：30 人，先到先得'), '30 人');
      expect(extractQuota('名额：25'), '25 人');
      expect(extractQuota('人数不限'), isNull);
      expect(extractQuota(''), isNull);
    });

    test('报名线索：QQ 群 / 手机号 / 扫码提示，手机号不重复算群号', () {
      final s = extractSignup('请加群 123456789 报名，联系人张三 13800138000，扫码进群');
      expect((s['qq'] as List).cast<String>(), ['123456789']);
      expect((s['phone'] as List).cast<String>(), ['13800138000']);
      expect((s['tips'] as List).cast<String>(), contains('扫码'));
      expect((s['contact_lines'] as List).length, greaterThan(0));
    });

    test('「群体/社群」等正常叙述不误判为报名线索', () {
      final s = extractSignup('面向青年群体的社群创始人，讲述人群画像');
      expect(s['contact_lines'], isNull);
    });

    test('校区与事后补录', () {
      expect(campusOf({'hdmc': '徐汇校区图书馆志愿服务'}), '徐汇');
      expect(campusOf({'hdmc': '奉贤校区 + 徐汇校区联合活动'}), '奉贤+徐汇');
      expect(campusOf({'hdmc': '线上活动'}), '未标注');
      expect(
          isBackfill({
            'hdkssj': '2026-03-01 09:00:00',
            'hdbmkssj': '2026-03-05 09:00:00',
          }),
          isTrue);
      expect(
          isBackfill({
            'hdkssj': '2026-03-10 09:00:00',
            'hdbmkssj': '2026-03-05 09:00:00',
          }),
          isFalse);
    });

    test('活动快照字段与开放接口同形', () {
      final snap = activitySnapshot({
        'id': 7,
        'hdmc': '讲座',
        'hdbmkssj': '2026-03-05 09:00:00',
        'hdbmjzsj': '2026-03-06 09:00:00',
        'hdkssj': '2026-03-10 09:00:00',
        'hdjssj': '2026-03-10 11:00:00',
        'zbfmc': '校团委',
        'hdms': '人数30人，请加群123456789',
        '_dlmc': '思想成长',
        '_lbmc': '讲座报告',
      });
      expect(snap['name'], '讲座');
      expect(snap['dlmc'], '思想成长');
      expect(snap['lbmc'], '讲座报告');
      expect(snap['quota'], '30 人');
      expect((snap['signup'] as Map)['qq'], ['123456789']);
      expect(snap['backfill'], isFalse);
    });
  });

  group('学校信息', () {
    test('按域名推导四个系统地址', () {
      final s = SchoolProfile.fromDomain('https://sit.edu.cn/');
      expect(s.authBase, 'https://authserver.sit.edu.cn/authserver');
      expect(s.jwxtBase, 'https://jwxt.sit.edu.cn');
      expect(s.xgBase, 'https://xg.sit.edu.cn');
      expect(s.ecardBase, 'https://ecard.sit.edu.cn');
      expect(s.isComplete, isTrue);
    });

    test('JSON 往返（多学校存档）', () {
      final list = [SchoolProfile.sit(), SchoolProfile.fromDomain('example.edu.cn')];
      final back = SchoolProfile.decodeList(SchoolProfile.encodeList(list));
      expect(back.length, 2);
      expect(back[0].name, '上海应用技术大学');
      expect(back[1].jwxtBase, 'https://jwxt.example.edu.cn');
    });

    test('学号打码', () {
      expect(maskStudentId('2211234567'), '221****67');
      expect(maskStudentId(''), '');
    });
  });

  group('服务器地址规范化（IP/域名:端口）', () {
    test('IP 与 localhost 默认 http，域名默认 https，去尾部斜杠', () {
      expect(AppState.normalizeServer('192.168.1.10:8000'), 'http://192.168.1.10:8000');
      expect(AppState.normalizeServer('127.0.0.1:8000'), 'http://127.0.0.1:8000');
      expect(AppState.normalizeServer('localhost:8000'), 'http://localhost:8000');
      expect(AppState.normalizeServer('my.server.cn:8443'), 'https://my.server.cn:8443');
      expect(AppState.normalizeServer('http://my.server.cn:8000/'), 'http://my.server.cn:8000');
      expect(AppState.normalizeServer('https://anticraft.top'), 'https://anticraft.top');
    });
  });
}
