// 控制器编排测试：注入内存 BatchStore，不依赖 Isar 原生库。
import 'package:flutter_test/flutter_test.dart';
import 'package:tea_core/tea_core.dart';
import 'package:tea_receiving/app/batch_controller.dart';
import 'package:tea_receiving/app/batch_store.dart';

const _positions = [
  SamplePosition.top,
  SamplePosition.middle,
  SamplePosition.bottom,
  SamplePosition.edge,
  SamplePosition.center,
];

Future<void> _registerSamples(BatchController c, int n) async {
  final lots = c.batch!.lots;
  for (var i = 0; i < n; i++) {
    await c.addSample(
      point: SamplePoint(
        lotId: lots[i % lots.length].id,
        position: _positions[i % _positions.length],
        x: 0.1,
        y: 0.2,
      ),
      actualPosition: _positions[i % _positions.length],
      grades: const [
        GradeShare(name: '单芽', percent: 60),
        GradeShare(name: '一芽一叶', percent: 30),
        GradeShare(name: '单片', percent: 10),
      ],
      water: SurfaceWater.none,
      odors: const [OffOdorType.none],
    );
  }
}

void main() {
  test('完整工作流：建批→多茶园票→绑篓→一篓分称→抽样→核对→收青', () async {
    final c = BatchController(pointCode: 'P01', operator: '甲', store: InMemoryBatchStore());
    final arrived = DateTime(2026, 9, 15, 12);
    await c.startBatch(arrivedAt: arrived, registeredAt: arrived);
    await c.addLot(
      blockId: 'BLK-A',
      method: PickingMethod.handOneBudOneLeaf,
      pickStart: arrived.subtract(const Duration(hours: 3)),
      pickEnd: arrived.subtract(const Duration(hours: 3)),
    );
    await c.addLot(
      blockId: 'BLK-B',
      method: PickingMethod.machine,
      pickStart: arrived.subtract(const Duration(hours: 2)),
      pickEnd: arrived.subtract(const Duration(hours: 2)),
    );
    await c.bindBasket('BK-P01-00001');
    await c.addWeighing(
        basketCode: 'BK-P01-00001',
        grossKg: 9.4,
        tareKg: 0.4,
        at: arrived,
        splitPart: 1);
    await c.addWeighing(
        basketCode: 'BK-P01-00001',
        grossKg: 6.4,
        tareKg: 0.4,
        at: arrived.add(const Duration(minutes: 5)),
        splitPart: 2);

    final plan = c.buildPlan(6);
    expect(plan.points.map((p) => p.lotId).toSet().length, 2);
    await _registerSamples(c, 6);

    final report = await c.runChecks();
    expect(report.blocks, isEmpty);
    final fin = await c.finalize('两个茶园分别核对，鲜叶正常，收');
    expect(fin.ok, isTrue);
    expect(c.batch!.status, ReceiptStatus.finalized);
    // (9.4-0.4)+(6.4-0.4)=15.0，逐次相加
    expect(c.batch!.totalNetKg, closeTo(15.0, 0.001));
  });

  test('雨损：未重贴前 block；重贴后旧码称量保留、新码可继续称', () async {
    final store = InMemoryBatchStore();
    final c = BatchController(pointCode: 'P01', operator: '甲', store: store);
    final arrived = DateTime(2026, 9, 15, 12);
    await c.startBatch(arrivedAt: arrived, registeredAt: arrived);
    await c.addLot(
      blockId: 'BLK-A',
      method: PickingMethod.handOneBudOneLeaf,
      pickStart: arrived.subtract(const Duration(hours: 3)),
      pickEnd: arrived.subtract(const Duration(hours: 3)),
    );
    await c.bindBasket('BK-P01-00001');
    await c.addWeighing(
        basketCode: 'BK-P01-00001', grossKg: 9, tareKg: 0.4, at: arrived);
    await _registerSamples(c, 5);
    await c.reportLabelDamage('BK-P01-00001', '雨损辨认');
    var r = await c.runChecks();
    expect(r.blocks.any((i) => i.code == IssueCode.labelDamaged), isTrue);

    await c.relabel(
      oldCode: 'BK-P01-00001',
      newCode: 'BK-P01-00099',
      container: ContainerType.bambooBasket,
    );
    await c.addWeighing(
        basketCode: 'BK-P01-00099',
        grossKg: 4,
        tareKg: 0.4,
        at: arrived.add(const Duration(minutes: 5)),
        splitPart: 2);
    r = await c.runChecks();
    expect(r.blocks, isEmpty);
    expect(c.batch!.weighings.first.basketCode, 'BK-P01-00001');
    // 每次写操作都落到内存存储
    expect(store.items.values.single.weighings.length, 2);
  });

  test('先摊后登记：采样计划落在摊放匾，未补登记也允许建批', () async {
    final c = BatchController(pointCode: 'P01', operator: '甲', store: InMemoryBatchStore());
    final arrived = DateTime(2026, 9, 15, 12);
    await c.startBatch(arrivedAt: arrived, alreadySpread: true);
    await c.addLot(
      blockId: 'BLK-A',
      method: PickingMethod.handOneBudOneLeaf,
      pickStart: arrived.subtract(const Duration(hours: 3)),
      pickEnd: arrived.subtract(const Duration(hours: 3)),
    );
    expect(c.batch!.registeredAt, isNull);
    expect(c.batch!.spreadStartedAt, arrived);
    final plan = c.buildPlan(5);
    expect(
      plan.points.every((p) =>
          p.position == SamplePosition.spreadTray ||
          p.position == SamplePosition.edge ||
          p.position == SamplePosition.center),
      isTrue,
    );
    await c.registerNow(arrived.add(const Duration(minutes: 40)));
    expect(c.batch!.registeredAt, isNotNull);
  });
}
