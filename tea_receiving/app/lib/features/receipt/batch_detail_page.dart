import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:isar/isar.dart';
import 'package:provider/provider.dart';
import 'package:tea_core/tea_core.dart';

import '../../app/batch_controller.dart';

import '../../db/collections.dart';
import '../sampling/sampling_page.dart';
import '../transport/batch_qr_page.dart';
import '../transport/bind_basket_page.dart';
import '../weigh/weigh_page.dart';
import 'check_page.dart';

/// 批次工作台：基本信息 / 绑篓 / 称重 / 抽样 / 核对。
class BatchDetailPage extends StatefulWidget {
  const BatchDetailPage({super.key, required this.batchId, this.initialTab});

  final String batchId;
  final String? initialTab;

  @override
  State<BatchDetailPage> createState() => _BatchDetailPageState();
}

class _BatchDetailPageState extends State<BatchDetailPage> {
  ReceivingBatch? _batch;
  late int _index;

  static const _routes = ['/bind', '/weigh', '/sample', '/check'];

  @override
  void initState() {
    super.initState();
    _index = widget.initialTab == null ? 0 : _routes.indexOf(widget.initialTab!) + 1;
    if (_index < 0) _index = 0;
    _load();
  }

  Future<void> _load() async {
    final isar = context.read<Isar>();
    final c = context.read<BatchController>();
    final rec = await isar.batchRecords
        .filter()
        .batchIdEqualTo(widget.batchId)
        .findFirst();
    if (!mounted) return;
    if (rec != null) {
      setState(() => _batch =
          ReceivingBatch.fromJson(jsonDecode(rec.payloadJson)));
    }
    // 若打开的是控制器当前批次，跟随控制器实时刷新
    if (c.batch?.id == widget.batchId) {
      _batch = c.batch;
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<BatchController>();
    final current = context.read<BatchController>().batch;
    final b = current?.id == widget.batchId ? current : _batch;
    if (b == null) {
      return const Scaffold(body: Center(child: Text('批次不存在或尚未同步到本机')));
    }
    final pages = <Widget>[
      _InfoTab(batch: b),
      const BindBasketPage(),
      const WeighPage(),
      const SamplingPage(),
      const CheckPage(),
    ];
    return Scaffold(
      appBar: AppBar(title: Text('${b.code} · ${b.status.label}')),
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.info_outline), label: '信息'),
          NavigationDestination(icon: Icon(Icons.qr_code_2), label: '绑篓'),
          NavigationDestination(icon: Icon(Icons.scale), label: '称重'),
          NavigationDestination(icon: Icon(Icons.science), label: '抽样'),
          NavigationDestination(icon: Icon(Icons.fact_check), label: '核对'),
        ],
      ),
    );
  }
}

class _InfoTab extends StatelessWidget {
  const _InfoTab({required this.batch});
  final ReceivingBatch batch;

  @override
  Widget build(BuildContext context) {
    final b = batch;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.qr_code_2),
            label: const Text('显示运输批二维码'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const BatchQrPage()),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text('到场：${b.arrivedAt}', style: const TextStyle(fontSize: 16)),
        Row(
          children: [
            Expanded(child: Text('登记：${b.registeredAt ?? '尚未补登记（先摊后登记）'}')),
            if (b.registeredAt == null)
              TextButton(
                onPressed: () async {
                  await context.read<BatchController>().registerNow(DateTime.now());
                },
                child: const Text('立即补登记'),
              ),
          ],
        ),
        if (b.spreadStartedAt != null) Text('摊放：${b.spreadStartedAt}'),
        if (b.labelDamaged)
          Card(
            color: Colors.red.shade50,
            child: ListTile(
              leading: const Icon(Icons.water_drop, color: Colors.red),
              title: const Text('标签受雨损坏'),
              subtitle: Text('${b.damagedBasketCode}\n${b.relabelNote}'),
            ),
          ),
        const Divider(),
        Text('鲜叶票（${b.lots.length} 张，事实按票保留）',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        for (final l in b.lots)
          Card(
            child: ListTile(
              title: Text('区块 ${l.blockId} · ${l.picking.label}'),
              subtitle: Text('采摘：${l.pickedAt.start} ~ ${l.pickedAt.end}'),
            ),
          ),
        const Divider(),
        Text('照片 ${b.photos.length} 张',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        for (final p in b.photos)
          ListTile(
            dense: true,
            leading: const Icon(Icons.image_outlined),
            title: Text(p.tag.label),
            subtitle: Text(p.localPath),
          ),
      ],
    );
  }
}
