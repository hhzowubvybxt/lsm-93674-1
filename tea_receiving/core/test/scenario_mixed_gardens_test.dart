import 'package:tea_core/tea_core.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

/// 场景一：多个茶园的鲜叶混装在同一运输批。
void main() {
  test('混装：区块/采法/采摘时间/容器/芽叶组成/红变按票分别保留', () {
    final arrived = DateTime(2026, 9, 15, 12);
    final b = batch('b1', arrived: arrived);

    final lA = lot('L-A', 'BLK-A',
        pickStart: arrived.subtract(const Duration(hours: 5)),
        method: PickingMethod.handOneBudOneLeaf);
    final lB = lot('L-B', 'BLK-B',
        pickStart: arrived.subtract(const Duration(hours: 3)),
        method: PickingMethod.machine);
    b
      ..register(arrived)
      ..addLot(lA)
      ..addLot(lB)
      ..bindBasket('BK-P01-00001')
      ..bindBasket('BK-P01-00002');
    b.addWeighing(weigh('w1',
        batchId: 'b1', basket: 'BK-P01-00001', gross: 12, at: arrived));
    b.addWeighing(weigh('w2',
        batchId: 'b1', basket: 'BK-P01-00002', gross: 8, at: arrived));

    // 每个茶园都必须抽到小样
    b.addSample(sample('s1',
        batchId: 'b1',
        lotId: 'L-A',
        pos: SamplePosition.top,
        grades: shares(70, 25, 5)));
    b.addSample(sample('s2',
        batchId: 'b1',
        lotId: 'L-A',
        pos: SamplePosition.middle,
        grades: shares(68, 26, 6)));
    b.addSample(sample('s3',
        batchId: 'b1',
        lotId: 'L-A',
        pos: SamplePosition.bottom,
        grades: shares(65, 28, 7)));
    b.addSample(sample('s4',
        batchId: 'b1',
        lotId: 'L-B',
        pos: SamplePosition.edge,
        grades: shares(20, 40, 40)));
    b.addSample(sample('s5',
        batchId: 'b1',
        lotId: 'L-B',
        pos: SamplePosition.center,
        grades: shares(18, 42, 40)));

    final svc = ReceivingService(clock: FixedClock(arrived).call);
    final r = svc.check(b);

    // 混装只是一条提示，不是错误；两张票各自事实保留
    final mixed = r.bySeverity(Severity.info)
        .where((i) => i.code == IssueCode.mixedGardens);
    expect(mixed, hasLength(1));
    expect(b.isMixedGardens, isTrue);
    expect(b.lots.map((l) => l.blockId).toSet(), {'BLK-A', 'BLK-B'});
    expect(b.lots.map((l) => l.picking).toSet(),
        {PickingMethod.handOneBudOneLeaf, PickingMethod.machine});
    expect(r.blocks, isEmpty, reason: '覆盖到位时不应有 block');

    // A 园单芽占比与 B 园差异巨大，但系统不算一个"大批平均级配"：
    // 各小样事实独立，差异提示供人工参考，不产生等级结论
    final spread = r.warnings
        .where((i) => i.code == IssueCode.gradeCompositionSpread);
    expect(spread, isNotEmpty);
    expect(b.samples.first.gradeShares.first.percent, 70);
    expect(b.samples.last.gradeShares.first.percent, 18);
  });

  test('混装：漏掉某个茶园的小样 → block，人工逐条确认前不能收青', () {
    final arrived = DateTime(2026, 9, 15, 12);
    final b = batch('b2', arrived: arrived)
      ..register(arrived)
      ..addLot(lot('L-A', 'BLK-A',
          pickStart: arrived.subtract(const Duration(hours: 4))))
      ..addLot(lot('L-B', 'BLK-B',
          pickStart: arrived.subtract(const Duration(hours: 4))))
      ..bindBasket('BK-P01-00001');
    b.addWeighing(
        weigh('w1', batchId: 'b2', basket: 'BK-P01-00001', gross: 10, at: arrived));
    for (var i = 0; i < 5; i++) {
      b.addSample(sample('s$i',
          batchId: 'b2',
          lotId: 'L-A',
          pos: const [
            SamplePosition.top,
            SamplePosition.middle,
            SamplePosition.bottom,
            SamplePosition.edge,
            SamplePosition.center,
          ][i]));
    }

    final svc = ReceivingService();
    final r = svc.check(b);
    final block = r.blocks
        .firstWhere((i) => i.code == IssueCode.sampleCoverageThin);
    expect(block.facts['unsampledLotIds'], ['L-B']);

    final fin = svc.finalize(b, by: '张三', note: '先收了再说');
    expect(fin.ok, isFalse);
    expect(fin.openBlockKeys, contains(startsWith('sampleCoverageThin')));
    expect(b.status, isNot(ReceiptStatus.finalized));

    // 补抽 L-B 后仍须满足位置覆盖；人工确认全部 block 才能收青
    b.addSample(sample('sB1',
        batchId: 'b2',
        lotId: 'L-B',
        pos: SamplePosition.bottom));
    final r2 = svc.check(b);
    expect(svc.openBlocks(b, r2), isEmpty);
    final fin2 =
        svc.finalize(b, by: '张三', note: '两个茶园小样均已核对，正常收青');
    expect(fin2.ok, isTrue);
    expect(b.status, ReceiptStatus.finalized);
    expect(b.finalizedBy, '张三');
  });
}
