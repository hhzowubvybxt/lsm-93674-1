import 'package:tea_core/tea_core.dart';
import 'package:test/test.dart';

void main() {
  group('采摘时间区间', () {
    test('只有区间时给出采后时长范围', () {
      final arrived = DateTime(2026, 9, 15, 14);
      final iv = TimeInterval(
        start: DateTime(2026, 9, 15, 5),
        end: DateTime(2026, 9, 15, 7),
      );
      final r = iv.postHarvestHours(arrived);
      expect(r.minHours, 7.0); // 14 - 最晚采摘 7 点
      expect(r.maxHours, 9.0); // 14 - 最早采摘 5 点
      expect(iv.isPoint, isFalse);
      expect(TimeInterval.point(arrived).isPoint, isTrue);
    });
  });

  group('芽叶级配', () {
    test('合计必须接近 100%', () {
      expect(
        () => validateGradeShares(const [
          GradeShare(name: '单芽', percent: 50),
          GradeShare(name: '单片', percent: 20),
        ]),
        throwsArgumentError,
      );
      validateGradeShares(const [
        GradeShare(name: '单芽', percent: 61),
        GradeShare(name: '一芽一叶', percent: 30),
        GradeShare(name: '单片', percent: 10),
      ]); // 101% 在 2% 容差内
    });
  });
}
