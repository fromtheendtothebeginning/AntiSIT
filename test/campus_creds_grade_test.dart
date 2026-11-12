import 'package:campus_core/campus_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('直连模式的年级随凭据持久化', () {
    final c = CampusCreds()
      ..studentId = '25110001'
      ..grade = '2027';
    final restored = CampusCreds.fromJson(c.toJson());
    expect(restored.grade, '2027');
    expect(restored.hasGrade, isTrue);

    final bad = CampusCreds()..grade = '27';
    expect(bad.hasGrade, isFalse);
  });

  test('学校档案的自签证书开关随档案持久化，默认关闭', () {
    final s = SchoolProfile.sit();
    expect(s.allowSelfSigned, isFalse, reason: '默认必须严格校验 TLS');

    s.allowSelfSigned = true;
    final restored = SchoolProfile.decodeList(SchoolProfile.encodeList([s])).single;
    expect(restored.allowSelfSigned, isTrue);

    final legacy = SchoolProfile.decodeList(
        '[{"name":"旧档案","authBase":"https://a","jwxtBase":"https://b",'
        '"xgBase":"https://c","ecardBase":"https://d"}]').single;
    expect(legacy.allowSelfSigned, isFalse, reason: '旧 JSON 没有该字段时按严格模式处理');
  });
}
