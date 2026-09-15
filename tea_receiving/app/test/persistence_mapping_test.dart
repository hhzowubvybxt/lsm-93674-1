// Isar FFI 原生库仅面向 Android/iOS（Linux 桌面只随 x64），
// 主机测试用 tea_core 的内存仓储验证持久化契约；
// Isar 集合与仓储实现的字段映射由 flutter analyze + build_runner 生成保证。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tea_core/tea_core.dart';
import 'package:tea_receiving/db/collections.dart';

void main() {
  test('BatchRecord 载荷可完整还原领域批次（含局部事实）', () {
    final arrived = DateTime(2026, 9, 15, 12);
    final b = ReceivingBatch(
      id: 'b1',
      code: 'RC-P01-00001',
      pointId: 'P01',
      arrivedAt: arrived,
      registeredAt: arrived,
    );
    b
      ..addLot(LeafLot(
        id: 'L1',
        blockId: 'BLK-A',
        picking: PickingMethod.machine,
        pickedAt: TimeInterval(
          start: arrived.subtract(const Duration(hours: 5)),
          end: arrived.subtract(const Duration(hours: 4)),
        ),
      ))
      ..bindBasket('BK-P01-00001')
      ..reportLabelDamage('BK-P01-00001', '雨淋');
    b.addWeighing(Weighing(
      id: 'w1',
      batchId: 'b1',
      basketCode: 'BK-P01-00001',
      grossKg: 9,
      tareKg: 0.5,
      weighedAt: arrived,
    ));
    b.addSample(Sample(
      id: 's1',
      batchId: 'b1',
      lotId: 'L1',
      position: SamplePosition.bottom,
      drawnAt: arrived,
      gradeShares: const [
        GradeShare(name: '单芽', percent: 40),
        GradeShare(name: '一芽二叶', percent: 60),
      ],
      water: SurfaceWater.wet,
      offOdors: const [OffOdorType.fermented],
      red: RedDamageLevel.severe,
      hotSpot: true,
    ));

    // 模拟 IsarBatchRepository.upsert 的序列化
    final payload = jsonEncode(b.toJson());
    final rec = BatchRecord(
      batchId: b.id,
      code: b.code,
      pointId: b.pointId,
      payloadJson: payload,
      status: b.status.index,
      updatedAt: arrived,
    );
    rec.syncState = SyncState.pendingLocal.index;

    // 模拟 findById 反序列化
    final restored =
        ReceivingBatch.fromJson(jsonDecode(rec.payloadJson) as Map<String, dynamic>);
    expect(restored.lots.single.picking, PickingMethod.machine);
    expect(restored.samples.single.red, RedDamageLevel.severe);
    expect(restored.samples.single.hotSpot, isTrue);
    expect(restored.samples.single.water, SurfaceWater.wet);
    expect(restored.labelDamaged, isTrue);
    expect(restored.totalNetKg, 8.5);

    // 队列表行
    final q = SyncQueueRecord(
      entity: 'receivingBatch',
      entityId: 'b1',
      payload: payload,
      createdAt: arrived,
    );
    expect(q.synced, isFalse);
    expect(jsonDecode(q.payload)['id'], 'b1');
  });

  test('内存仓储满足断网 upsert/队列顺序契约（Isar 实现同构）', () async {
    final repo = InMemoryBatchRepository();
    final b = ReceivingBatch(
      id: 'x',
      code: 'RC-P01-00002',
      pointId: 'P01',
      arrivedAt: DateTime(2026, 9, 15, 12),
    );
    await repo.upsert(b);
    await repo.upsert(b);
    expect(await repo.queue.length(), 2);
    final items = await repo.queue.all();
    expect(items[0].seq < items[1].seq, isTrue);
    expect(await repo.findByCode('RC-P01-00002'), isNotNull);
  });
}
