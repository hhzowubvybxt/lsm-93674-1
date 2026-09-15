/// 竹篓二维码编解码。
///
/// 内容格式：`TEA-BASKET/<版本>/<站点码>/<篓号>#<CRC8>`
/// CRC 只用于在雨损/污渍/拍摄反光造成误读时尽早发现错误；
/// 无法识别时 App 允许手工录入篓号，业务不阻塞。
library;

import '../receiving_errors.dart';

class BasketQr {
  const BasketQr({
    required this.pointCode,
    required this.basketSerial,
    this.version = 1,
  });

  final int version;
  final String pointCode;
  final String basketSerial;

  String get basketCode => 'BK-$pointCode-$basketSerial';

  String encode() {
    final body = 'TEA-BASKET/$version/$pointCode/$basketSerial';
    return '$body#${crc8(body).toRadixString(16).padLeft(2, '0').toUpperCase()}';
  }

  /// 解析成功返回 BasketQr；无法识别（雨损、污损、手工码）返回 null，
  /// 调用方应转人工录入而不是报错中断。
  static BasketQr? tryParse(String raw) {
    final s = raw.trim();
    final hash = s.lastIndexOf('#');
    String body;
    String? crc;
    if (hash >= 0) {
      body = s.substring(0, hash);
      crc = s.substring(hash + 1);
    } else {
      body = s;
    }
    final parts = body.split('/');
    if (parts.length != 4 || parts[0] != 'TEA-BASKET') return null;
    final v = int.tryParse(parts[1]);
    if (v == null) return null;
    if (crc != null) {
      final got = int.tryParse(crc, radix: 16);
      if (got == null || got != crc8(body)) return null;
    }
    return BasketQr(
      version: v,
      pointCode: parts[2],
      basketSerial: parts[3],
    );
  }
}

/// CRC-8/MAXIM (poly 0x31, init 0x00)。
int crc8(String data) {
  var crc = 0;
  for (final byte in data.codeUnits) {
    crc ^= byte;
    for (var i = 0; i < 8; i++) {
      crc = (crc & 1) == 1 ? (crc >> 1) ^ 0x8C : crc >> 1;
    }
  }
  return crc & 0xFF;
}

/// 运输批的二维码（竹篓绑定运输批时贴在篓上的批次签）。
class BatchQr {
  const BatchQr({required this.pointCode, required this.serial});

  final String pointCode;

  /// 批序号（如 0007）。
  final String serial;

  String get batchCode => 'RC-$pointCode-$serial';

  String encode() {
    final body = 'TEA-BATCH/1/$pointCode/$serial';
    return '$body#${crc8(body).toRadixString(16).padLeft(2, '0').toUpperCase()}';
  }

  static ({String pointCode, String batchCode})? tryParse(String raw) {
    final s = raw.trim();
    final body = s.contains('#') ? s.substring(0, s.lastIndexOf('#')) : s;
    final crc = s.contains('#') ? s.substring(s.lastIndexOf('#') + 1) : null;
    final parts = body.split('/');
    if (parts.length == 4 && parts[0] == 'TEA-BATCH') {
      if (crc != null) {
        final got = int.tryParse(crc, radix: 16);
        if (got == null || got != crc8(body)) return null;
      }
      final code = 'RC-${parts[2]}-${parts[3]}';
      return (pointCode: parts[2], batchCode: code);
    }
    // 手工批码兜底：RC-站点-序号
    final m = RegExp(r'^RC-([A-Z0-9]+)-(\d+)$').firstMatch(s);
    if (m != null) return (pointCode: m.group(1)!, batchCode: s);
    return null;
  }
}

/// 站点生成顺序篓号（供 App 发签用）。
String formatBasketCode(String pointCode, int seq) {
  if (seq <= 0) {
    throw ReceivingValidationError('篓号序号必须为正整数');
  }
  return 'BK-$pointCode-${seq.toString().padLeft(5, '0')}';
}
