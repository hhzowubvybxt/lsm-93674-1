/// 联网后把 Isar 待同步队列按顺序推到服务器。
/// 断网/服务器不可达时保留队列，不影响现场收青。
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:isar/isar.dart';
import 'package:tea_core/tea_core.dart';

import '../db/collections.dart';

/// 服务器端点抽象（现场无内网时可注入假实现/空实现）。
abstract class ReceivingApi {
  /// 上传成功返回 true；幂等键为 entityId。
  Future<bool> push({
    required String entity,
    required String entityId,
    required Map<String, dynamic> payload,
  });
}

class HttpReceivingApi implements ReceivingApi {
  HttpReceivingApi(this.baseUrl, {http.Client? client})
      : _client = client ?? http.Client();
  final String baseUrl;
  final http.Client _client;

  @override
  Future<bool> push(
      {required String entity,
      required String entityId,
      required Map<String, dynamic> payload}) async {
    final resp = await _client.post(
      Uri.parse('$baseUrl/receiving/$entity/$entityId'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );
    return resp.statusCode >= 200 && resp.statusCode < 300;
  }
}

class NullReceivingApi implements ReceivingApi {
  @override
  Future<bool> push(
          {required String entity,
          required String entityId,
          required Map<String, dynamic> payload}) async =>
      false; // 未配置端点：一律视为未同步
}

class SyncService {
  SyncService({required this.isar, required this.api});
  final Isar isar;
  final ReceivingApi api;

  Future<SyncSummary> flushPending() async {
    final pending = await isar.syncQueueRecords
        .filter()
        .syncedEqualTo(false)
        .sortByCreatedAt()
        .findAll();
    var pushed = 0;
    final failed = <String>[];
    for (final q in pending) {
      try {
        final ok = await api.push(
          entity: q.entity,
          entityId: q.entityId,
          payload: jsonDecode(q.payload) as Map<String, dynamic>,
        );
        if (ok) {
          await isar.writeTxn(() async {
            q.synced = true;
            await isar.syncQueueRecords.put(q);
            final batch = await isar.batchRecords
                .filter()
                .batchIdEqualTo(q.entityId)
                .findFirst();
            if (batch != null) {
              batch.syncState = SyncState.synced.index;
              await isar.batchRecords.put(batch);
            }
          });
          pushed++;
        } else {
          failed.add(q.entityId);
          break; // 顺序队列：失败即停，避免乱序
        }
      } on Object {
        failed.add(q.entityId);
        break;
      }
    }
    return SyncSummary(pushed: pushed, remaining: pending.length - pushed,
        failed: failed);
  }

  Future<int> pendingCount() async {
    try {
      return await isar.syncQueueRecords
          .filter()
          .syncedEqualTo(false)
          .count();
    } on Object {
      return 0;
    }
  }
}

class SyncSummary {
  const SyncSummary(
      {required this.pushed, required this.remaining, required this.failed});
  final int pushed;
  final int remaining;
  final List<String> failed;
}
