import 'package:flutter/material.dart';
import 'package:isar/isar.dart';
import 'package:provider/provider.dart';

import '../../db/collections.dart';
import '../../services/sync_service.dart';

/// 离线队列：断网期间的批次/称量/抽样都在本机；联网后一键顺序推送。
class OfflinePage extends StatefulWidget {
  const OfflinePage({super.key});

  @override
  State<OfflinePage> createState() => _OfflinePageState();
}

class _OfflinePageState extends State<OfflinePage> {
  List<SyncQueueRecord> _pending = [];
  String? _message;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final isar = context.read<Isar>();
    final rows =
        await isar.syncQueueRecords.filter().syncedEqualTo(false).findAll();
    if (mounted) setState(() => _pending = rows);
  }

  Future<void> _flush() async {
    setState(() => _busy = true);
    final s = context.read<SyncService>();
    final summary = await s.flushPending();
    setState(() {
      _busy = false;
      _message = summary.remaining == 0
          ? '全部已同步（${summary.pushed} 条）'
          : '已同步 ${summary.pushed} 条，剩余 ${summary.remaining} 条'
              '${summary.failed.isEmpty ? "" : "，停于 ${summary.failed.first}"}';
    });
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('离线队列')),
      body: Column(
        children: [
          Card(
            color: Colors.orange.shade50,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  const Icon(Icons.cloud_off),
                  const SizedBox(width: 10),
                  Expanded(child: Text('待同步写操作 ${_pending.length} 条\n'
                      '断网期间收青不受影响')),
                  FilledButton.icon(
                    icon: const Icon(Icons.sync),
                    label: const Text('联网同步'),
                    onPressed: _busy ? null : _flush,
                  ),
                ],
              ),
            ),
          ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Align(
                  alignment: Alignment.centerLeft, child: Text(_message!)),
            ),
          Expanded(
            child: ListView.builder(
              itemCount: _pending.length,
              itemBuilder: (_, i) {
                final q = _pending[i];
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.upload_outlined),
                  title: Text('${q.entity} · ${q.entityId}'),
                  subtitle: Text('${q.createdAt}'),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
