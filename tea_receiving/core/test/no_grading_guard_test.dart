import 'dart:convert';

import 'package:tea_core/tea_core.dart';
import 'package:test/test.dart';

/// 护栏：系统不自动决定等级或价格。
/// 用序列化白名单锁定字段：聚合 JSON 中不得出现 grade/price/level 等字段。
void main() {
  test('领域模型不存在等级/价格字段（序列化白名单护栏）', () {
    final b = ReceivingBatch(
      id: 'x',
      code: 'RC-P01-0001',
      pointId: 'P01',
      arrivedAt: DateTime(2026, 9, 15, 12),
    );
    final j = jsonEncode(b.toJson());
    for (final banned in ['"price"', '"grade_"', '"level"', '"amount"', '"单价"']) {
      expect(j, isNot(contains(banned)), reason: '发现自动定级定价字段：$banned');
    }
  });

  test('收青结论只存人工文本；无提示时普通收青不产生任何 block', () {
    final arrived = DateTime(2026, 9, 15, 12);
    final b = ReceivingBatch(
      id: 'y',
      code: 'RC-P01-0002',
      pointId: 'P01',
      arrivedAt: arrived,
    )
      ..register(arrived)
      ..addLot(LeafLot(
        id: 'L1',
        blockId: 'BLK-A',
        picking: PickingMethod.handOneBudOneLeaf,
        pickedAt: TimeInterval.point(
            arrived.subtract(const Duration(hours: 3))),
      ))
      ..bindBasket('BK-P01-00001');
    b.addWeighing(Weighing(
      id: 'w1',
      batchId: 'y',
      basketCode: 'BK-P01-00001',
      grossKg: 9,
      tareKg: 0.5,
      weighedAt: arrived,
    ));
    for (var i = 0; i < 5; i++) {
      b.addSample(Sample(
        id: 's$i',
        batchId: 'y',
        lotId: 'L1',
        position: const [
          SamplePosition.top,
          SamplePosition.middle,
          SamplePosition.bottom,
          SamplePosition.edge,
          SamplePosition.center,
        ][i],
        drawnAt: arrived,
        gradeShares: const [
          GradeShare(name: '单芽', percent: 60),
          GradeShare(name: '一芽一叶', percent: 30),
          GradeShare(name: '单片', percent: 10),
        ],
        water: SurfaceWater.none,
        offOdors: const [OffOdorType.none],
      ));
    }
    final svc = ReceivingService();
    final r = svc.check(b, baskets: {
      'BK-P01-00001':
          Basket(code: 'BK-P01-00001', container: ContainerType.bambooBasket),
    });
    expect(r.blocks, isEmpty);
    final fin = svc.finalize(b, by: '收青员', note: '状态正常');
    expect(fin.ok, isTrue);
    expect(b.decisionNote, '状态正常');
  });
}
