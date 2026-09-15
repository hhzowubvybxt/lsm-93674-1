/// tea_core 仓储端口的 Isar 实现。
library;

import 'dart:convert';

import 'package:isar/isar.dart';
import 'package:tea_core/tea_core.dart';

import '../db/collections.dart';

class IsarBatchRepository implements BatchRepository {
  IsarBatchRepository(this.isar);
  final Isar isar;

  @override
  Future<ReceivingBatch?> findById(String id) async {
    final r =
        await isar.batchRecords.filter().batchIdEqualTo(id).findFirst();
    return r == null ? null : ReceivingBatch.fromJson(jsonDecode(r.payloadJson));
  }

  @override
  Future<ReceivingBatch?> findByCode(String code) async {
    final r =
        await isar.batchRecords.filter().codeEqualTo(code).findFirst();
    return r == null ? null : ReceivingBatch.fromJson(jsonDecode(r.payloadJson));
  }

  @override
  Future<List<ReceivingBatch>> findAll(
      {bool includeFinalized = true}) async {
    final q = isar.batchRecords.where();
    final all = await q.findAll();
    return all
        .map((r) => ReceivingBatch.fromJson(jsonDecode(r.payloadJson)))
        .where((b) =>
            includeFinalized || b.status != ReceiptStatus.finalized)
        .toList();
  }

  @override
  Future<PendingMutation> upsert(ReceivingBatch batch) {
    final payload = jsonEncode(batch.toJson());
    return isar.writeTxn(() async {
      final existing = await isar.batchRecords
          .filter()
          .batchIdEqualTo(batch.id)
          .findFirst();
      final rec = existing ?? BatchRecord(
        batchId: batch.id,
        code: batch.code,
        pointId: batch.pointId,
        payloadJson: payload,
        status: batch.status.index,
        updatedAt: DateTime.now(),
      );
      rec
        ..code = batch.code
        ..pointId = batch.pointId
        ..payloadJson = payload
        ..status = batch.status.index
        ..syncState = SyncState.pendingLocal.index
        ..updatedAt = DateTime.now();
      await isar.batchRecords.put(rec);

      final q = SyncQueueRecord(
        entity: 'receivingBatch',
        entityId: batch.id,
        payload: payload,
        createdAt: DateTime.now(),
      );
      await isar.syncQueueRecords.put(q);

      return PendingMutation(
        seq: q.id.toInt(),
        entity: q.entity,
        entityId: q.entityId,
        payload: payload,
        createdAt: q.createdAt,
      );
    });
  }
}

class IsarBasketRepository implements BasketRepository {
  IsarBasketRepository(this.isar);
  final Isar isar;

  @override
  Future<Basket?> findByCode(String code) async {
    final r =
        await isar.basketRecords.filter().codeEqualTo(code).findFirst();
    return r == null ? null : Basket.fromJson(jsonDecode(r.payloadJson));
  }

  @override
  Future<List<Basket>> findAll() async {
    final rows = await isar.basketRecords.where().findAll();
    return rows
        .map((r) => Basket.fromJson(jsonDecode(r.payloadJson)))
        .toList();
  }

  @override
  Future<void> save(Basket basket) => isar.writeTxn(() async {
        final existing = await isar.basketRecords
            .filter()
            .codeEqualTo(basket.code)
            .findFirst();
        final rec = existing ??
            BasketRecord(
              code: basket.code,
              payloadJson: jsonEncode(basket.toJson()),
            );
        rec
          ..payloadJson = jsonEncode(basket.toJson())
          ..active = basket.active;
        await isar.basketRecords.put(rec);
      });
}

class IsarBlockRepository implements BlockRepository {
  IsarBlockRepository(this.isar);
  final Isar isar;

  @override
  Future<GardenBlock?> findById(String id) async {
    final r =
        await isar.blockRecords.filter().blockIdEqualTo(id).findFirst();
    return r == null
        ? null
        : GardenBlock.fromJson(jsonDecode(r.payloadJson));
  }

  @override
  Future<List<GardenBlock>> findAll() async {
    final rows = await isar.blockRecords.where().findAll();
    return rows
        .map((r) => GardenBlock.fromJson(jsonDecode(r.payloadJson)))
        .toList();
  }

  @override
  Future<void> save(GardenBlock block) => isar.writeTxn(() async {
        final existing = await isar.blockRecords
            .filter()
            .blockIdEqualTo(block.id)
            .findFirst();
        final rec = existing ??
            BlockRecord(
              blockId: block.id,
              name: block.name,
              payloadJson: jsonEncode(block.toJson()),
            );
        rec.payloadJson = jsonEncode(block.toJson());
        await isar.blockRecords.put(rec);
      });
}
