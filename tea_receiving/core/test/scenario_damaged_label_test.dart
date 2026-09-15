import 'package:tea_core/tea_core.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

/// 场景四：竹篓标签受雨损坏。
void main() {
  ReceivingBatch ready(String id, DateTime arrived) {
    final b = batch(id, arrived: arrived)..register(arrived);
    b
      ..addLot(lot('L1', 'BLK-A',
          pickStart: arrived.subtract(const Duration(hours: 3))))
      ..bindBasket('BK-P01-00001');
    b.addWeighing(
        weigh('w1', batchId: id, basket: 'BK-P01-00001', gross: 9, at: arrived));
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

  test('雨损未处置 → block；拍照留证并重贴后降为 info，可收青', () {
    final arrived = DateTime(2026, 9, 15, 12);
    final b = ready('b1', arrived);
    b.reportLabelDamage('BK-P01-00001', '标签被雨泡烂，篓号最后一位辨认不清');
    b.addPhoto(LotPhoto(
      id: 'p1',
      batchId: 'b1',
      basketCode: 'BK-P01-00001',
      tag: PhotoTag.labelPhoto,
      localPath: '/photos/p1.jpg',
      takenAt: arrived.add(const Duration(minutes: 2)),
    ));

    final svc = ReceivingService();
    final r0 = svc.check(b);
    final damaged = r0.blocks
        .where((i) => i.code == IssueCode.labelDamaged)
        .toList();
    expect(damaged, hasLength(1));
    expect(svc.finalize(b, by: '赵六', note: '收').ok, isFalse);

    // 人工核对身份后重贴新签
    b.relabel(oldCode: 'BK-P01-00001', newCode: 'BK-P01-00088');
    final r1 = svc.check(b, baskets: {
      'BK-P01-00088': Basket(
          code: 'BK-P01-00088', container: ContainerType.bambooBasket),
    });
    expect(
      r1.bySeverity(Severity.info)
          .any((i) => i.code == IssueCode.labelDamaged),
      isTrue,
    );
    final fin = svc.finalize(b,
        by: '赵六', note: '雨损标签已人工核对、拍照、重贴新签 BK-P01-00088');
    expect(fin.ok, isTrue);
    // 留证照片未丢
    expect(b.photos.single.tag, PhotoTag.labelPhoto);
  });

  test('雨损重贴：旧码历史保留、新码生效，称量按旧码仍可追溯', () {
    final arrived = DateTime(2026, 9, 15, 12);
    final b = ready('b2', arrived);
    b.reportLabelDamage('BK-P01-00001', '雨损，手工核对为张师傅的篓');
    b.addPhoto(LotPhoto(
      id: 'p1',
      batchId: 'b2',
      basketCode: 'BK-P01-00001',
      tag: PhotoTag.labelPhoto,
      localPath: '/photos/p1.jpg',
      takenAt: arrived.add(const Duration(minutes: 2)),
    ));
    // 补打新签
    b.relabel(oldCode: 'BK-P01-00001', newCode: 'BK-P01-00088');
    expect(b.basketCodes, ['BK-P01-00088']);
    // 历史称量仍是旧码，不被覆盖
    expect(b.weighings.single.basketCode, 'BK-P01-00001');
    // 新码可以继续称量
    b.addWeighing(weigh('w2',
        batchId: 'b2',
        basket: 'BK-P01-00088',
        gross: 4.2,
        at: arrived.add(const Duration(minutes: 5)),
        splitPart: 2));
    expect(b.netByBasket.containsKey('BK-P01-00001'), isTrue);
    expect(b.netByBasket.containsKey('BK-P01-00088'), isTrue);

    final svc = ReceivingService();
    final r = svc.check(b, baskets: {
      'BK-P01-00088': Basket(
          code: 'BK-P01-00088', container: ContainerType.bambooBasket),
      'BK-P01-00001': Basket(
          code: 'BK-P01-00001', container: ContainerType.bambooBasket),
    });
    // 已重贴 → 仅留痕提示
    expect(
      r.issues.where((i) => i.code == IssueCode.labelDamaged),
      hasLength(1),
    );
    expect(
      r.bySeverity(Severity.info)
          .any((i) => i.code == IssueCode.labelDamaged),
      isTrue,
    );
    expect(svc.openBlocks(b, r), isEmpty);
    final fin = svc.finalize(b,
        by: '赵六', note: '雨损标签已人工核对、拍照、重贴新签 BK-P01-00088');
    expect(fin.ok, isTrue);

    // 往返序列化保留重贴痕迹与旧码称量
    final j = b.toJson();
    final restored = ReceivingBatch.fromJson(j);
    expect(restored.relabelNote, contains('BK-P01-00001'));
    expect(restored.weighings.first.basketCode, 'BK-P01-00001');
    expect(restored.photos.single.localPath, '/photos/p1.jpg');
  });

  test('雨损二维码 CRC 失败时只转人工，不抛异常', () {
    expect(BasketQr.tryParse('TEA-BASKET/1/P01/00001#ZZ'), isNull);
    expect(BasketQr.tryParse(''), isNull);
  });
}
