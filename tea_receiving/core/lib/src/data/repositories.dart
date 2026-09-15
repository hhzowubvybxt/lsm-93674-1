/// 仓储端口（由 App 层用 Isar 实现）。
///
/// 内核只定义端口，保证业务规则不绑定任何本地数据库/网络。
library;

import '../domain/aggregate.dart';
import '../domain/entities.dart';

abstract class BatchRepository {
  Future<ReceivingBatch?> findById(String id);
  Future<ReceivingBatch?> findByCode(String code);
  Future<List<ReceivingBatch>> findAll({bool includeFinalized = true});

  /// 保存（离线可用）。返回进入待同步队列的载荷。
  Future<PendingMutation> upsert(ReceivingBatch batch);
}

abstract class BasketRepository {
  Future<Basket?> findByCode(String code);
  Future<List<Basket>> findAll();
  Future<void> save(Basket basket);
}

abstract class BlockRepository {
  Future<GardenBlock?> findById(String id);
  Future<List<GardenBlock>> findAll();
  Future<void> save(GardenBlock block);
}

/// 断网期间暂存的一次写操作；联网后按 [seq] 顺序上传。
class PendingMutation {
  const PendingMutation({
    required this.seq,
    required this.entity,
    required this.entityId,
    required this.payload,
    required this.createdAt,
  });

  final int seq;
  final String entity;
  final String entityId;
  final String payload;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'seq': seq,
        'entity': entity,
        'entityId': entityId,
        'payload': payload,
        'createdAt': createdAt.toIso8601String(),
      };
}

/// 待同步队列端口。
abstract class SyncQueue {
  Future<void> enqueue(PendingMutation m);
  Future<List<PendingMutation>> all();
  Future<void> remove(int seq);
  Future<int> length();
}
