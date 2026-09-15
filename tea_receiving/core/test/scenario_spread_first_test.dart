import 'package:tea_core/tea_core.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

/// 场景五：鲜叶到场后先摊开，过一段时间才登记；摊后篓底局部闷热。
void main() {
  test('先摊后登记：采后时长以到场为准，抽样改在摊放匾', () {
    final arrived = DateTime(2026, 9, 15, 12);
    final spread = arrived.add(const Duration(minutes: 2));
    final registered = arrived.add(const Duration(minutes: 40));
    final picked = arrived.subtract(const Duration(hours: 4));

    final b = batch('b1', arrived: arrived, spreadAt: spread, registered: registered);
    b
      ..addLot(lot('L1', 'BLK-A', pickStart: picked))
      ..bindBasket('BK-P01-00001')
      ..addWeighing(weigh('w1',
          batchId: 'b1', basket: 'BK-P01-00001', gross: 9, at: registered));

    // 摊开后抽样计划全部落在摊放匾/边缘/中心，不再要求篓底
    final planner = SamplingPlanner(
      random: SequencedRandom(const [
        0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 0.95, //
      ]),
    );
    final plan = planner.plan(
      batchId: 'b1',
      lotIds: ['L1'],
      sampleCount: 5,
      alreadySpread: true,
    );
    expect(plan.points.map((p) => p.position).contains(SamplePosition.bottom),
        isFalse);
    expect(plan.points.map((p) => p.position),
        contains(SamplePosition.spreadTray));

    for (var i = 0; i < plan.points.length; i++) {
      final p = plan.points[i];
      b.addSample(Sample(
        id: 's$i',
        batchId: 'b1',
        lotId: p.lotId,
        position: p.position,
        randomX: p.x,
        randomY: p.y,
        drawnAt: registered.add(Duration(minutes: i)),
        gradeShares: shares(61, 30, 9),
        water: SurfaceWater.slight,
        offOdors: const [OffOdorType.none],
      ));
    }

    final clockObj = FixedClock(registered);
    final svc = ReceivingService(clock: clockObj.call);
    final r = svc.check(b);

    // 先摊后登记是 info（40 分钟），不阻塞；文字明确以到场时刻算采后时长
    final spreadIssue = r.infos
        .where((i) => i.code == IssueCode.spreadBeforeRegister)
        .single;
    expect(spreadIssue.facts['delayMinutes'], 38);
    // 摊开后没有篓底抽样也不算覆盖不足
    expect(
      r.blocks.where((i) => i.code == IssueCode.sampleMissingPosition),
      isEmpty,
    );
    // 采后时长仍从到场(12:00)对采摘(08:00)算 4h，不因晚登记而虚高
    final range = b.postHarvestRange()!;
    expect(range.maxHours, 4.0);
  });

  test('局部闷热：单份小样红变/发热被逐条保留，不被大批平均覆盖', () {
    final arrived = DateTime(2026, 9, 15, 12);
    final b = batch('b2', arrived: arrived)..register(arrived);
    b
      ..addLot(lot('L1', 'BLK-A',
          pickStart: arrived.subtract(const Duration(hours: 4))))
      ..bindBasket('BK-P01-00001')
      ..addWeighing(weigh('w1',
          batchId: 'b2', basket: 'BK-P01-00001', gross: 9, at: arrived));

    const pos = [
      SamplePosition.top,
      SamplePosition.middle,
      SamplePosition.bottom,
      SamplePosition.edge,
      SamplePosition.center,
    ];
    for (var i = 0; i < 5; i++) {
      b.addSample(Sample(
        id: 's$i',
        batchId: 'b2',
        lotId: 'L1',
        position: pos[i],
        drawnAt: arrived.add(const Duration(minutes: 5)),
        gradeShares: shares(60, 31, 9),
        water: i == 2 ? SurfaceWater.wet : SurfaceWater.none,
        offOdors: const [OffOdorType.none],
        red: i == 2 ? RedDamageLevel.local : RedDamageLevel.none,
        hotSpot: i == 2,
      ));
    }

    final svc = ReceivingService();
    final r = svc.check(b, baskets: {
      'BK-P01-00001':
          Basket(code: 'BK-P01-00001', container: ContainerType.plasticBag),
    });

    final hot = r.blocks
        .where((i) => i.code == IssueCode.localHotSpot)
        .toList();
    expect(hot, hasLength(1));
    expect(hot.single.facts['sampleId'], 's2');
    expect(hot.single.facts['position'], 'bottom');
    // 塑料袋不透气警告 + 篓底湿样警告
    expect(
      r.warnings
          .any((i) => i.code == IssueCode.nonBreathableContainer),
      isTrue,
    );
    final wet = r.warnings.where((i) => i.code == IssueCode.wetSurface).toList();
    expect(wet.single.facts['sampleId'], 's2');

    // 其他 4 份小样的红变等级保持 none——没有"平均红变"这种东西
    final noneCount = b.samples
        .where((s) => s.red == RedDamageLevel.none)
        .length;
    expect(noneCount, 4);

    // 异味独立 block（药味），与红变逐条并存
    b.addSample(Sample(
      id: 's6',
      batchId: 'b2',
      lotId: 'L1',
      position: SamplePosition.middle,
      drawnAt: arrived.add(const Duration(minutes: 8)),
      gradeShares: shares(58, 33, 9),
      water: SurfaceWater.none,
      offOdors: const [OffOdorType.pesticide],
    ));
    final r2 = svc.check(b);
    expect(
      r2.blocks.where((i) => i.code == IssueCode.offOdor).single.facts['sampleId'],
      's6',
    );

    // 人工逐条处置闷热与异味（接受/挑出问题篓），系统不自动定级定价
    for (final issue in svc.openBlocks(b, r2)) {
      b.addAck(ManualAck(
        issueCode: svc.issueKey(issue),
        by: '收青员甲',
        at: arrived.add(const Duration(minutes: 30)),
        accepted: true,
        note: '问题部位已单独摊放挑拣',
      ));
    }
    final fin = svc.finalize(b,
        by: '收青员甲', note: '篓底闷热小样与异味小样均已人工挑出，其余正常收');
    expect(fin.ok, isTrue);
    // 模型里没有等级/价格字段：人工结论只存文本
    expect(b.decisionNote, isNot(contains('价')));
  });
}
