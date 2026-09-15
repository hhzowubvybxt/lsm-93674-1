import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:isar/isar.dart';
import 'package:provider/provider.dart';
import 'package:tea_core/tea_core.dart';

import '../../app/batch_controller.dart';
import '../../db/collections.dart';
import 'batch_detail_page.dart';

/// 本机收青记录（断网可查）。
class BatchListPage extends StatefulWidget {
  const BatchListPage({super.key});

  @override
  State<BatchListPage> createState() => _BatchListPageState();
}

class _BatchListPageState extends State<BatchListPage> {
  List<ReceivingBatch> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final isar = context.read<Isar>();
    final rows = await isar.batchRecords.where().sortByUpdatedAtDesc().findAll();
    if (mounted) {
      setState(() {
        _items = rows
            .map((r) => ReceivingBatch.fromJson(jsonDecode(r.payloadJson)))
            .toList();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('本机收青记录（${_items.length}）')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView.separated(
          itemCount: _items.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final b = _items[i];
            return ListTile(
              title: Text(b.code),
              subtitle: Text('${b.status.label} · ${b.lots.length} 票'
                  ' · 净 ${b.totalNetKg}kg · 样 ${b.samples.length}'),
              trailing: b.status == ReceiptStatus.finalized
                  ? const Icon(Icons.check_circle, color: Colors.green)
                  : const Icon(Icons.edit_note),
              onTap: () async {
                final c = context.read<BatchController>();
                await c.load(b.id);
                if (context.mounted) {
                  await Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => BatchDetailPage(batchId: b.id),
                  ));
                  _load();
                }
              },
            );
          },
        ),
      ),
    );
  }
}
