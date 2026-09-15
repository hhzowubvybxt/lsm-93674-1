/// 收青批工作流控制器：把 Flutter 界面操作映射到 tea_core 领域动作，
/// 所有写操作即时落入 Isar（断网可用）。
library;


import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';
import 'package:tea_core/tea_core.dart';

import '../db/collections.dart';
import 'batch_store.dart';


class BatchController extends ChangeNotifier {
  BatchController({
    this.isar,
    required this.pointCode,
    required this.operator,
    BatchStore? store,
  })  : _store = store,
        _svc = ReceivingService();

  final Isar? isar;
  final BatchStore? _store;
  final String pointCode;
  final String operator;
  final ReceivingService _svc;

  ReceivingBatch? _batch;
  final Map<String, Basket> _baskets = {};
  CheckReport? _report;

  ReceivingBatch? get batch => _batch;
  CheckReport? get report => _report;
  bool get hasBatch => _batch != null;

  String get nextBatchCode {
    final now = DateTime.now();
    return 'RC-$pointCode-${now.millisecondsSinceEpoch % 100000}';
  }

  /// 新建运输批。[alreadySpread] = 到场即先摊开，稍后再补登记。
  Future<void> startBatch({
    required DateTime arrivedAt,
    bool alreadySpread = false,
    DateTime? spreadAt,
    DateTime? registeredAt,
  }) async {
    final b = ReceivingBatch(
      id: 'B-${DateTime.now().microsecondsSinceEpoch}',
      code: nextBatchCode,
      pointId: pointCode,
      arrivedAt: arrivedAt,
      spreadStartedAt: alreadySpread ? (spreadAt ?? arrivedAt) : null,
      registeredAt: registeredAt,
    );
    if (alreadySpread && registeredAt == null) {
      // 先摊后登记：合法，registeredAt 留空，界面提示补登记。
    } else {
      b.register(registeredAt ?? arrivedAt);
    }
    _batch = b;
    _report = null;
    await _persist();
    notifyListeners();
  }

  Future<void> registerNow(DateTime at) async {
    _batch?.register(at);
    await _persist();
    notifyListeners();
  }

  Future<void> markSpread(DateTime at) async {
    _batch?.markSpread(at);
    await _persist();
    notifyListeners();
  }

  // ---- 鲜叶票（多茶园混装时调用多次） ----
  Future<void> addLot({
    required String blockId,
    required PickingMethod method,
    required DateTime pickStart,
    required DateTime pickEnd,
    String? team,
    List<GradeShare> reported = const [],
  }) async {
    final b = _batch;
    if (b == null) return;
    b.addLot(LeafLot(
      id: 'L-${DateTime.now().microsecondsSinceEpoch}',
      blockId: blockId,
      picking: method,
      pickedAt: TimeInterval(start: pickStart, end: pickEnd),
      harvestTeam: team,
      reportedComposition: reported,
    ));
    await _persist();
    notifyListeners();
  }

  // ---- 竹篓绑定 ----
  Future<void> bindBasket(String basketCode) async {
    final b = _batch;
    if (b == null) return;
    b.bindBasket(basketCode);
    if (_store == null) {
      final cached = await isar!.basketRecords
          .filter()
          .codeEqualTo(basketCode)
          .findFirst();
      if (cached != null) {
        _baskets[basketCode] =
            Basket.fromJson(jsonDecode(cached.payloadJson));
      }
    }
    await _persist();
    notifyListeners();
  }

  Future<void> registerBasketProfile(
      String code, ContainerType type, double tareKg) async {
    final basket = Basket(
        code: code,
        container: type,
        tareKg: tareKg,
        issuedAt: DateTime.now());
    _baskets[code] = basket;
    final db = isar;
    if (_store == null && db != null) {
      await db.writeTxn(() async {
        await db.basketRecords.put(BasketRecord(
          code: code,
          payloadJson: jsonEncode(basket.toJson()),
        ));
      });
    }
    notifyListeners();
  }

  Future<void> reportLabelDamage(String code, String note) async {
    _batch?.reportLabelDamage(code, note);
    await _persist();
    notifyListeners();
  }

  Future<void> relabel({
    required String oldCode,
    required String newCode,
    required ContainerType container,
    double tareKg = 0,
  }) async {
    final b = _batch;
    if (b == null) return;
    b.relabel(oldCode: oldCode, newCode: newCode);
    final basket =
        Basket(code: newCode, container: container, tareKg: tareKg);
    _baskets[newCode] = basket;
    _baskets[oldCode] = basket; // 容器核对顺旧码也能找到
    await registerBasketProfile(newCode, container, tareKg);
    await _persist();
    notifyListeners();
  }

  // ---- 称量 ----
  Future<void> addWeighing({
    required String basketCode,
    required double grossKg,
    required double tareKg,
    required DateTime at,
    int splitPart = 1,
    String? scaleId,
  }) async {
    final b = _batch;
    if (b == null) return;
    b.addWeighing(Weighing(
      id: 'W-${DateTime.now().microsecondsSinceEpoch}',
      batchId: b.id,
      basketCode: basketCode,
      grossKg: grossKg,
      tareKg: tareKg,
      weighedAt: at,
      splitPart: splitPart,
      scaleId: scaleId,
    ));
    await _persist();
    notifyListeners();
  }

  // ---- 抽样 ----
  SamplingPlan buildPlan(int count) {
    final b = _batch!;
    return const SamplingPlanner().plan(
      batchId: b.id,
      lotIds: b.lots.map((l) => l.id).toList(),
      sampleCount: count,
      alreadySpread: b.spreadStartedAt != null,
    );
  }

  Future<void> addSample({
    required SamplePoint point,
    required SamplePosition actualPosition,
    required List<GradeShare> grades,
    required SurfaceWater water,
    required List<OffOdorType> odors,
    RedDamageLevel red = RedDamageLevel.none,
    BruiseLevel bruise = BruiseLevel.none,
    bool hotSpot = false,
    double? weightG,
    String note = '',
  }) async {
    final b = _batch;
    if (b == null) return;
    b.addSample(Sample(
      id: 'S-${DateTime.now().microsecondsSinceEpoch}',
      batchId: b.id,
      lotId: point.lotId,
      position: actualPosition,
      randomX: point.x,
      randomY: point.y,
      drawnAt: DateTime.now(),
      gradeShares: grades,
      water: water,
      offOdors: odors,
      red: red,
      bruise: bruise,
      hotSpot: hotSpot,
      weightG: weightG,
      note: note,
    ));
    await _persist();
    notifyListeners();
  }

  Future<void> addPhoto(LotPhoto photo) async {
    _batch?.addPhoto(photo);
    final db = isar;
    if (_store == null && db != null) {
      await db.writeTxn(() async {
        await db.photoRecords.put(PhotoRecord(
          photoId: photo.id,
          batchId: photo.batchId,
          localPath: photo.localPath,
          tag: photo.tag.index,
          takenAt: photo.takenAt,
        ));
      });
    }
    await _persist();
    notifyListeners();
  }

  // ---- 核对与人工处置 ----
  Future<CheckReport> runChecks({Map<String, double> declaredNet = const {}}) async {
    final b = _batch!;
    _report = _svc.check(b, baskets: _baskets, declaredNetByBasket: declaredNet);
    notifyListeners();
    return _report!;
  }

  Future<void> acknowledge(CheckIssue issue,
      {required bool accepted, required String note}) async {
    final b = _batch;
    if (b == null) return;
    b.addAck(ManualAck(
      issueCode: _svc.issueKey(issue),
      by: operator,
      at: DateTime.now(),
      accepted: accepted,
      note: note,
    ));
    _report = _svc.check(b, baskets: _baskets);
    await _persist();
    notifyListeners();
  }

  bool isAcked(CheckIssue issue) =>
      _batch?.acks.any((a) => a.issueCode == _svc.issueKey(issue)) ?? false;

  List<CheckIssue> get openBlocks {
    final b = _batch;
    final r = _report;
    if (b == null || r == null) return const [];
    return _svc.openBlocks(b, r);
  }

  /// 完成收青。系统只校验每条 block 都有对应的人工处置，等级/价格不在此处出现。
  Future<ReceiptFinalization> finalize(String note) async {
    final b = _batch!;
    final result = _svc.finalize(b, by: operator, note: note);
    await _persist();
    notifyListeners();
    return result;
  }

  Future<void> _persist() async {
    final b = _batch;
    if (b == null) return;
    final st = _store;
    if (st != null) {
      await st.save(b);
      return;
    }
    final db = isar;
    if (db == null) return;
    await db.writeTxn(() async {
      final payload = jsonEncode(b.toJson());
      final existing = await db.batchRecords
          .filter()
          .batchIdEqualTo(b.id)
          .findFirst();
      final rec = existing ??
          BatchRecord(
            batchId: b.id,
            code: b.code,
            pointId: b.pointId,
            payloadJson: payload,
            status: b.status.index,
            updatedAt: DateTime.now(),
          );
      rec
        ..payloadJson = payload
        ..status = b.status.index
        ..updatedAt = DateTime.now();
      await db.batchRecords.put(rec);
      await db.syncQueueRecords.put(SyncQueueRecord(
        entity: 'receivingBatch',
        entityId: b.id,
        payload: payload,
        createdAt: DateTime.now(),
      ));
    });
  }

  Future<void> load(String batchId) async {
    final db = isar;
    if (db == null) return;
    final rec =
        await db.batchRecords.filter().batchIdEqualTo(batchId).findFirst();
    if (rec != null) {
      _batch =
          ReceivingBatch.fromJson(jsonDecode(rec.payloadJson));
      _report = _svc.check(_batch!, baskets: _baskets);
      notifyListeners();
    }
  }
}
