import 'package:tea_core/tea_core.dart';
import 'package:test/test.dart';

void main() {
  group('竹篓二维码', () {
    test('编码后可解析，CRC 防止误读', () {
      final qr = const BasketQr(pointCode: 'P01', basketSerial: '00123');
      final code = qr.encode();
      expect(code, startsWith('TEA-BASKET/1/P01/00123#'));
      final parsed = BasketQr.tryParse(code)!;
      expect(parsed.pointCode, 'P01');
      expect(parsed.basketSerial, '00123');
      expect(parsed.basketCode, 'BK-P01-00123');

      // 雨损污渍导致末位误读 → CRC 不通过 → 返回 null，转人工录入
      final damaged = '${code.substring(0, code.length - 1)}0';
      expect(BasketQr.tryParse(damaged), isNull);

      // 完全不是二维码格式（手工条）→ null，不抛异常
      expect(BasketQr.tryParse('手写篓号 张师傅'), isNull);
    });

    test('运输批二维码与手工批码均可解析', () {
      final code = const BatchQr(pointCode: 'P01', serial: '0007').encode();
      final r = BatchQr.tryParse(code)!;
      expect(r.batchCode, 'RC-P01-0007');
      expect(BatchQr.tryParse('RC-P01-0007')!.batchCode, 'RC-P01-0007');
      expect(BatchQr.tryParse('无法辨认'), isNull);
    });

    test('篓号序号必须为正', () {
      expect(() => formatBasketCode('P01', 0), throwsArgumentError);
      expect(formatBasketCode('P01', 7), 'BK-P01-00007');
    });
  });
}
