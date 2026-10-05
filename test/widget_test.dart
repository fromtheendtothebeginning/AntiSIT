import 'package:flutter_test/flutter_test.dart';

import 'package:campus_service/app_state.dart';

void main() {
  test('inferSemester 学年学期推算', () {
    // 9-12月：新学年第一学期
    expect(AppState.inferSemester(DateTime(2026, 9, 1)), ('2026', '3'));
    expect(AppState.inferSemester(DateTime(2026, 12, 31)), ('2026', '3'));
    // 3-8月：上一学年第二学期
    expect(AppState.inferSemester(DateTime(2026, 5, 1)), ('2025', '12'));
    expect(AppState.inferSemester(DateTime(2026, 8, 20)), ('2025', '12'));
    // 1-2月：上一学年第一学期（期末季）
    expect(AppState.inferSemester(DateTime(2026, 1, 15)), ('2025', '3'));
    expect(AppState.inferSemester(DateTime(2026, 2, 20)), ('2025', '3'));
  });
}
