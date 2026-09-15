import 'dart:convert';

import 'package:tea_core/tea_core.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  test('断网：upsert 本地可查且进入待同步队列，顺序不乱', () async {
    final repo = InMemoryBatchRepository();
    final arrived = DateTime(2026, 9, 15, 12);
    final b = batch('b1', arrived: arrived)
      ..register(arrived)
      ..addLot(lot('L1', 'BLK-A',
          pickStart: arrived.subtract(const Duration(hours: 4))))
      ..bindBasket('BK-P01-00001');
    b.addWeighing(
        weigh('w1', batchId: 'b1', basket: 'BK-P01-00001', gross: 9, at: arrived));

    final m1 = await repo.upsert(b);
    b.markSpread(arrived.add(const Duration(minutes: 5)));
    final m2 = await repo.upsert(b);
    expect(m2.seq, m1.seq + 1);
    expect(await repo.queue.length(), 2);
    final queued = await repo.queue.all();
    expect(queued.map((e) => e.seq).toList(), [m1.seq, m2.seq]);
    // 载荷是完整 JSON，联网后可直接 POST
    final decoded = jsonDecode(queued.last.payload) as Map<String, dynamic>;
    expect(decoded['id'], 'b1');
    expect(decoded['spreadStartedAt'], isNotNull);
    await repo.queue.remove(m1.seq);
    expect(await repo.queue.length(), 1);
    expect(await repo.findByCode('RC-P01-0001'), isNotNull);
  });

  test('聚合往返 JSON：多 lot/分称/小样/照片/人工确认全部保留', () {
    final arrived = DateTime(2026, 9, 15, 12);
    final b = batch('jx', arrived: arrived)
      ..register(arrived)
      ..addLot(lot('L1', 'BLK-A',
          pickStart: arrived.subtract(const Duration(hours: 4))))
      ..bindBasket('BK-P01-00001');
    b
      ..addWeighing(weigh('w1',
          batchId: 'jx', basket: 'BK-P01-00001', gross: 9, at: arrived))
      ..addWeighing(weigh('w2',
          batchId: 'jx',
          basket: 'BK-P01-00001',
          gross: 7,
          at: arrived.add(const Duration(minutes: 5)),
          splitPart: 2))
      ..addPhoto(LotPhoto(
        id: 'ph1',
        batchId: 'jx',
        tag: PhotoTag.spreadSample,
        localPath: '/x.jpg',
        takenAt: arrived,
      ))
      ..addAck(ManualAck(
        issueCode: 'localHotSpot|sampleId=s2',
        by: '甲',
        at: arrived,
        accepted: true,
      ));
    b.addSample(sample('s1',
        batchId: 'jx', lotId: 'L1', pos: SamplePosition.bottom,
        red: RedDamageLevel.local, hotSpot: true));

    final restored = ReceivingBatch.fromJson(b.toJson());
    expect(restored.weighings, hasLength(2));
    expect(restored.totalNetKg, b.totalNetKg);
    expect(restored.samples.single.hotSpot, isTrue);
    expect(restored.photos.single.tag, PhotoTag.spreadSample);
    expect(restored.acks.single.issueCode, 'localHotSpot|sampleId=s2');
    expect(restored.lots.single.picking, PickingMethod.handOneBudOneLeaf);
  });
}
