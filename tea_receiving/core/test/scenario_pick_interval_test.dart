import 'package:tea_core/tea_core.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

/// 场景三：茶农只记得"早上 5 点到 8 点之间采的"，采摘时间只有区间。
void main() {
  ReceivingBatch readyBatch(String id, DateTime arrived, LeafLot lot) {
    final b = batch(id, arrived: arrived)..register(arrived);
    b
      ..addLot(lot)
      ..bindBasket('BK-P01-00001');
    b.addWeighing(weigh('w1',
        batchId: id, basket: 'BK-P01-00001', gross: 9, at: arrived));
    for (var i = 0; i < 5; i++) {
      b.addSample(sample('s$i',
          batchId: id,
          lotId: 'L1',
          pos: const [
            SamplePosition.top,
            SamplePosition.middle,
            SamplePosition.bottom,
            SamplePosition.edge,
            SamplePosition.center,
          ][i],
          at: arrived.add(const Duration(minutes: 5))));
    }
    return b;
  }

  test('宽区间且区间跨超时线 → warning，不自动下结论', () {
    final arrived = DateTime(2026, 9, 15, 14);
    final b = readyBatch(
        'b1',
        arrived,
        lot('L1', 'BLK-A',
            pickStart: DateTime(2026, 9, 15, 5),
            pickEnd: DateTime(2026, 9, 15, 8))); // 采后 6~9h，限 8h

    final svc = ReceivingService();
    final r = svc.check(b);
    final long = r.warnings
        .where((i) => i.code == IssueCode.postHarvestLong)
        .toList();
    expect(long, hasLength(1));
    expect(long.single.facts['minHours'], 6.0);
    expect(long.single.facts['maxHours'], 9.0);
    // 区间本身 3h，未超 maxPickIntervalHours(6h)，不额外报区间过宽
    expect(
      r.issues
          .where((i) => i.code == IssueCode.postHarvestUnknownInterval),
      isEmpty,
    );
    // warning 不是 block：人工知情即可收青，但系统不替人决定
    expect(svc.openBlocks(b, r), isEmpty);
    final fin = svc.finalize(b, by: '王五', note: '茶农自述上午采，鲜叶状态正常，收');
    expect(fin.ok, isTrue);
  });

  test('区间两端都已超时 → block；区间过宽另有警告', () {
    final arrived = DateTime(2026, 9, 15, 18);
    final b = readyBatch(
        'b2',
        arrived,
        lot('L1', 'BLK-A',
            pickStart: DateTime(2026, 9, 15, 0), // 采后 18~11h，区间 7h
            pickEnd: DateTime(2026, 9, 15, 7)));

    final svc = ReceivingService();
    final r = svc.check(b);
    final blocked = r.blocks
        .where((i) => i.code == IssueCode.postHarvestLong)
        .toList();
    expect(blocked, hasLength(1));
    expect(blocked.single.facts['minHours'], 11.0);
    final wide = r.warnings
        .where((i) => i.code == IssueCode.postHarvestUnknownInterval);
    expect(wide, hasLength(1)); // 区间 7h > 6h
  });

  test('精确时刻采后超时 → block 且事实里只有一个时长', () {
    final arrived = DateTime(2026, 9, 15, 20);
    final b = readyBatch(
        'b3',
        arrived,
        lot('L1', 'BLK-A',
            pickStart: DateTime(2026, 9, 15, 9))); // 正好 11h
    final r = ReceivingService().check(b);
    final blocked = r.blocks
        .firstWhere((i) => i.code == IssueCode.postHarvestLong);
    expect(blocked.facts['minHours'], 11.0);
    expect(blocked.facts['maxHours'], 11.0);
  });
}
