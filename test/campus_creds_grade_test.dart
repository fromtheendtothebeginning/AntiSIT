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
}
