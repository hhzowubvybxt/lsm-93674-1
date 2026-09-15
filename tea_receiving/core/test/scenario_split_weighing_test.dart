import 'package:tea_core/tea_core.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

/// 场景二：一只竹篓分两次称量（先倒一部分上秤）。
void main() {
  ReceivingBatch readyBatch(String id, DateTime arrived) {
    final b = batch(id, arrived: arrived)..register(arrived);
    b
      ..addLot(lot('L1', 'BLK-A',
          pickStart: arrived.subtract(const Duration(hours: 4))))
      ..bindBasket('BK-P01-00001');
    return b;
  }

  void coverSamples(ReceivingBatch b) {
    for (var i = 0; i < 5; i++) {
      b.addSample(sample('s$i',
          batchId: b.id,
          lotId: 'L1',
          pos: const [
            SamplePosition.top,
            SamplePosition.middle,
            SamplePosition.bottom,
            SamplePosition.edge,
            SamplePosition.center,
          ][i],
          at: b.arrivedAt.add(const Duration(minutes: 10))));
    }
  }

  test('一篓两次称量：净重相加，不用大批均值反推', () {
    final arrived = DateTime(2026, 9, 15, 12);
    final b = readyBatch('b1', arrived);
    b
      ..addWeighing(weigh('w1',
          batchId: 'b1',
          basket: 'BK-P01-00001',
          gross: 9.6,
          tare: 0.4,
          at: arrived,
          splitPart: 1))
      ..addWeighing(weigh('w2',
          batchId: 'b1',
          basket: 'BK-P01-00001',
          gross: 7.5,
          tare: 0.4,
          at: arrived.add(const Duration(minutes: 6)),
          splitPart: 2));
    coverSamples(b);

    // (9.6-0.4) + (7.5-0.4) = 9.2 + 7.1 = 16.3kg
    expect(b.netByBasket['BK-P01-00001'], 16.3);
    expect(b.totalNetKg, 16.3);
    expect(b.totalGrossKg, 17.1);

    final svc = ReceivingService();
    final r = svc.check(b);
    // 已勾选分称、毛重不同 → 不应误报重复过秤
    expect(
      r.issues.where((i) => i.code == IssueCode.duplicateWeighing),
      isEmpty,
    );
    expect(r.blocks, isEmpty);
  });

  test('同篓短时同重量且未声明分称 → 疑似重复过秤 block', () {
    final arrived = DateTime(2026, 9, 15, 12);
    final b = readyBatch('b2', arrived);
    b
      ..addWeighing(weigh('w1',
          batchId: 'b2', basket: 'BK-P01-00001', gross: 9.6, at: arrived))
      ..addWeighing(weigh('w2',
          batchId: 'b2',
          basket: 'BK-P01-00001',
          gross: 9.6,
          at: arrived.add(const Duration(minutes: 3))));
    coverSamples(b);

    final svc = ReceivingService();
    final r = svc.check(b);
    final dup =
        r.blocks.where((i) => i.code == IssueCode.duplicateWeighing).toList();
    expect(dup, hasLength(1));
    expect(dup.single.facts['basketCode'], 'BK-P01-00001');

    // 净重核对：联单自报 20kg，逐次净重合计 18.4kg，差 8% > 5% → 警告
    final r2 = svc.check(b, declaredNetByBasket: {'BK-P01-00001': 20});
    expect(
      r2.warnings.any((i) => i.code == IssueCode.netWeightMismatch),
      isTrue,
    );

    // 未经人工确认不能收青；人工确认（重复录入已删除/知悉）后可收青
    expect(svc.finalize(b, by: '李四', note: '收').ok, isFalse);
    b.addAck(ManualAck(
      issueCode: svc.issueKey(dup.single),
      by: '李四',
      at: arrived.add(const Duration(minutes: 20)),
      accepted: false,
      note: '确认为误重复，已在秤端删除一条',
    ));
    // 聚合里仍保留两条历史（审计事实），但人工已处置；核对结果仍会报 block，
    // 因有 ack 覆盖，openBlocks 为空，可以收青
    final r3 = svc.check(b);
    expect(svc.openBlocks(b, r3), isEmpty);
    expect(svc.finalize(b, by: '李四', note: '重复过秤已人工核实并处置').ok,
        isTrue);
  });

  test('未绑篓不能称量；重复提交同一称量记录被拒绝', () {
    final arrived = DateTime(2026, 9, 15, 12);
    final b = readyBatch('b3', arrived);
    expect(
      () => b.addWeighing(
          weigh('w1', batchId: 'b3', basket: 'BK-P01-00099', gross: 5, at: arrived)),
      throwsA(isA<ReceivingStateError>()),
    );
    final w = weigh('w1', batchId: 'b3', basket: 'BK-P01-00001', gross: 5, at: arrived);
    b.addWeighing(w);
    expect(() => b.addWeighing(w), throwsA(isA<ReceivingStateError>()));
  });
}
