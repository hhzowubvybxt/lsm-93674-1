/// 纯内存仓储实现：内核自测用，也演示 App 层 Isar 实现需要满足的契约。
library;

import '../domain/aggregate.dart';
import '../domain/enums.dart';
import '../domain/entities.dart';
import 'dart:convert';

import 'repositories.dart';

class InMemoryBatchRepository implements BatchRepository {
  final Map<String, ReceivingBatch> _store = {};
  final SyncQueue queue;
  int _seq = 0;

  InMemoryBatchRepository({SyncQueue? queue})
      : queue = queue ?? InMemorySyncQueue();

  @override
  Future<ReceivingBatch?> findById(String id) async => _store[id];

  @override
  Future<ReceivingBatch?> findByCode(String code) async {
    for (final b in _store.values) {
      if (b.code == code) return b;
    }
    return null;
  }

  @override
  Future<List<ReceivingBatch>> findAll(
          {bool includeFinalized = true}) async =>
      _store.values
          .where((b) =>
              includeFinalized || b.status != ReceiptStatus.finalized)
          .toList();

  @override
  Future<PendingMutation> upsert(ReceivingBatch batch) async {
    _store[batch.id] = batch;
    final m = PendingMutation(
      seq: ++_seq,
      entity: 'receivingBatch',
      entityId: batch.id,
      payload: jsonEncode(batch.toJson()),
      createdAt: DateTime.now(),
    );
    await queue.enqueue(m);
    return m;
  }
}

class InMemoryBasketRepository implements BasketRepository {
  final Map<String, Basket> _store = {};
  @override
  Future<Basket?> findByCode(String code) async => _store[code];
  @override
  Future<List<Basket>> findAll() async => _store.values.toList();
  @override
  Future<void> save(Basket basket) async => _store[basket.code] = basket;
}

class InMemoryBlockRepository implements BlockRepository {
  final Map<String, GardenBlock> _store = {};
  @override
  Future<GardenBlock?> findById(String id) async => _store[id];
  @override
  Future<List<GardenBlock>> findAll() async => _store.values.toList();
  @override
  Future<void> save(GardenBlock block) async => _store[block.id] = block;
}

class InMemorySyncQueue implements SyncQueue {
  final List<PendingMutation> _items = [];
  @override
  Future<void> enqueue(PendingMutation m) async => _items.add(m);
  @override
  Future<List<PendingMutation>> all() async =>
      List.unmodifiable(_items..sort((a, b) => a.seq.compareTo(b.seq)));
  @override
  Future<void> remove(int seq) async =>
      _items.removeWhere((m) => m.seq == seq);
  @override
  Future<int> length() async => _items.length;
}
