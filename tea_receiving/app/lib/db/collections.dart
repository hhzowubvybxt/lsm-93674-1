/// Isar 本地集合：断网批次、称重、抽样、照片、竹篓档案、待同步队列。
///
/// 这些是持久化 DTO，领域事实由 tea_core 的模型表达；
/// JSON 以字符串列保存，避免任何本地"平均字段"回写覆盖局部事实。
library;

import 'package:isar/isar.dart';

part 'collections.g.dart';

@collection
class BatchRecord {
  BatchRecord({
    required this.batchId,
    required this.code,
    required this.pointId,
    required this.payloadJson,
    required this.status,
    required this.updatedAt,
    this.syncState = 0,
  });

  Id id = Isar.autoIncrement;

  @Index(unique: true)
  late String batchId;

  @Index()
  late String code;
  late String pointId;

  /// ReceivingBatch.toJson() 的完整快照。
  late String payloadJson;

  /// ReceiptStatus.index
  late int status;

  /// 0=仅本机待同步，1=已同步（SyncState.index）
  late int syncState;
  late DateTime updatedAt;
}

@collection
class BasketRecord {
  BasketRecord({
    required this.code,
    required this.payloadJson,
    this.active = true,
  });

  Id id = Isar.autoIncrement;

  @Index(unique: true)
  late String code;

  late String payloadJson;
  late bool active;
}

@collection
class BlockRecord {
  BlockRecord({
    required this.blockId,
    required this.name,
    required this.payloadJson,
  });

  Id id = Isar.autoIncrement;

  @Index(unique: true)
  late String blockId;

  @Index()
  late String name;
  late String payloadJson;
}

@collection
class SyncQueueRecord {
  SyncQueueRecord({
    required this.entity,
    required this.entityId,
    required this.payload,
    required this.createdAt,
    this.synced = false,
  });

  Id id = Isar.autoIncrement;

  late String entity;

  @Index()
  late String entityId;

  late String payload;
  late DateTime createdAt;
  late bool synced;
}

/// 照片文件登记（缩略图/原图路径，相机拍照后写入；同步时上传）。
@collection
class PhotoRecord {
  PhotoRecord({
    required this.photoId,
    required this.batchId,
    required this.localPath,
    required this.tag,
    required this.takenAt,
    this.uploaded = false,
    this.remoteUrl,
  });

  Id id = Isar.autoIncrement;

  @Index(unique: true)
  late String photoId;

  @Index()
  late String batchId;

  late String localPath;

  /// PhotoTag.index
  late int tag;
  late DateTime takenAt;
  late bool uploaded;
  String? remoteUrl;
}
