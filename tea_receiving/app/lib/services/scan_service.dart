/// 二维码扫描封装：竹篓码、运输批码。
/// 识别失败（雨损/反光/手签）不抛错，调用方走手工录入。
library;

import 'package:collection/collection.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:tea_core/tea_core.dart';

sealed class ScanResult {
  const ScanResult();
}

class BasketScan extends ScanResult {
  const BasketScan(this.basketCode, this.container);
  final String basketCode;

  /// 码内没有容器信息时为 null，由档案补全。
  final ContainerType? container;
}

class BatchScan extends ScanResult {
  const BatchScan(this.pointCode, this.batchCode);
  final String pointCode;
  final String batchCode;
}

class UnrecognizedScan extends ScanResult {
  const UnrecognizedScan(this.raw);
  final String raw;
}

class ScanService {
  /// 把相机原始条码内容解释为业务码；CRC 不通过返回 UnrecognizedScan。
  static ScanResult interpret(String raw) {
    final bq = BasketQr.tryParse(raw);
    if (bq != null) {
      return BasketScan(bq.basketCode, null);
    }
    final rq = BatchQr.tryParse(raw);
    if (rq != null) {
      return BatchScan(rq.pointCode, rq.batchCode);
    }
    return UnrecognizedScan(raw);
  }

  /// mobile_scanner 回调适配。
  static ScanResult? fromBarcodeCapture(BarcodeCapture cap) {
    final raw = cap.barcodes.firstOrNull?.rawValue;
    if (raw == null || raw.isEmpty) return null;
    return interpret(raw);
  }
}
