/// 批次持久化端口：控制器只依赖它，Isar/内存各一份实现，
/// 让工作流逻辑在没有原生库的主机上也可完整测试。
library;

import 'package:tea_core/tea_core.dart';

abstract class BatchStore {
  Future<void> save(ReceivingBatch batch);
}

/// 纯内存实现（测试与演示用）。
class InMemoryBatchStore implements BatchStore {
  final Map<String, ReceivingBatch> items = {};
  @override
  Future<void> save(ReceivingBatch batch) async => items[batch.id] = batch;
}
