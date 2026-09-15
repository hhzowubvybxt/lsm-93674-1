import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tea_core/tea_core.dart';

import '../../app/batch_controller.dart';
import '../../services/sync_service.dart';
import '../offline/offline_page.dart';
import '../receipt/batch_detail_page.dart';
import '../receipt/batch_list_page.dart';
import '../transport/new_batch_page.dart';

/// 收青点主界面：六枚大按钮，手套湿手也能操作。
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageStateState();
}

class _HomePageStateState extends State<HomePage> {
  int _pending = 0;

  @override
  void initState() {
    super.initState();
    _refreshPending();
  }

  Future<void> _refreshPending() async {
    final n = await context.read<SyncService>().pendingCount();
    if (mounted) setState(() => _pending = n);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('鲜叶收青 · P01 收青点'),
        actions: [
          IconButton(
            tooltip: '离线队列',
            onPressed: () async {
              await Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const OfflinePage(),
              ));
              _refreshPending();
            },
            icon: Badge(
              label: Text('$_pending'),
              isLabelVisible: _pending > 0,
              child: const Icon(Icons.cloud_off),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _CurrentBatchCard(
                onOpen: () => _openCurrent(context),
                onPending: _refreshPending,
              ),
              const SizedBox(height: 16),
              Expanded(
                child: GridView.count(
                  crossAxisCount: 2,
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 14,
                  children: [
                    _BigButton(
                      icon: Icons.add_business,
                      label: '新运输批\n(多茶园可混装)',
                      color: Colors.green.shade700,
                      onTap: () => _start(context),
                    ),
                    _BigButton(
                      icon: Icons.qr_code_scanner,
                      label: '扫码绑竹篓\n(二维码)',
                      color: Colors.brown.shade600,
                      onTap: () => _requireBatch(
                          context, (c) => _goto(c, '/bind')),
                    ),
                    _BigButton(
                      icon: Icons.scale,
                      label: '过秤称重\n(一篓可分称)',
                      color: Colors.blueGrey.shade700,
                      onTap: () => _requireBatch(
                          context, (c) => _goto(c, '/weigh')),
                    ),
                    _BigButton(
                      icon: Icons.science,
                      label: '随机抽样\n(芽叶/水/异味)',
                      color: Colors.teal.shade700,
                      onTap: () => _requireBatch(
                          context, (c) => _goto(c, '/sample')),
                    ),
                    _BigButton(
                      icon: Icons.fact_check,
                      label: '核对处置\n(人工决定)',
                      color: Colors.deepOrange.shade700,
                      onTap: () => _requireBatch(
                          context, (c) => _goto(c, '/check')),
                    ),
                    _BigButton(
                      icon: Icons.history,
                      label: '收青记录\n(断网可查)',
                      color: Colors.indigo.shade600,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const BatchListPage()),
                      ),
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  '系统只核对事实并提示：等级与价格由人工决定',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black54),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _start(BuildContext context) async {
    final c = context.read<BatchController>();
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const NewBatchPage()));
    if (c.hasBatch && context.mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => BatchDetailPage(batchId: c.batch!.id)),
      );
      _refreshPending();
    }
  }

  void _requireBatch(
      BuildContext context, void Function(BuildContext) action) {
    final c = context.read<BatchController>();
    if (!c.hasBatch) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先点"新运输批"登记到场鲜叶')),
      );
      return;
    }
    action(context);
  }

  void _goto(BuildContext context, String route) {
    final id = context.read<BatchController>().batch!.id;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => BatchDetailPage(batchId: id, initialTab: route),
    ));
  }

  Future<void> _openCurrent(BuildContext context) async {
    final c = context.read<BatchController>();
    if (c.hasBatch) {
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => BatchDetailPage(batchId: c.batch!.id),
      ));
      _refreshPending();
    }
  }
}

class _CurrentBatchCard extends StatelessWidget {
  const _CurrentBatchCard({required this.onOpen, required this.onPending});

  final VoidCallback onOpen;
  final VoidCallback onPending;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<BatchController>();
    final b = c.batch;
    if (b == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Icon(Icons.inventory_2, size: 36, color: Colors.green.shade700),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('当前无在收批次\n鲜叶到场后先点"新运输批"',
                    style: TextStyle(fontSize: 15)),
              ),
            ],
          ),
        ),
      );
    }
    final open = c.openBlocks.length;
    return Card(
      color: b.status == ReceiptStatus.finalized
          ? Colors.green.shade50
          : Colors.orange.shade50,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(b.code,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text('鲜叶票 ${b.lots.length} 张 · 竹篓 ${b.basketCodes.length} 只'
                  ' · 净重 ${b.totalNetKg}kg · 小样 ${b.samples.length} 份'),
              const SizedBox(height: 4),
              Text('状态：${b.status.label}'
                  '${b.spreadStartedAt != null ? ' · 已先摊开' : ''}'
                  '${open > 0 ? ' · 待人工处置 $open 项' : ''}'),
            ],
          ),
        ),
      ),
    );
  }
}

class _BigButton extends StatelessWidget {
  const _BigButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 46, color: Colors.white),
              const SizedBox(height: 10),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
