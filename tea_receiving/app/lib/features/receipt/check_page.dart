import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tea_core/tea_core.dart';

import '../../app/batch_controller.dart';

/// 核对与人工处置。系统列出提示，收青员逐条确认；不出现等级/价格按钮。
class CheckPage extends StatefulWidget {
  const CheckPage({super.key});

  @override
  State<CheckPage> createState() => _CheckPageState();
}

class _CheckPageState extends State<CheckPage> {
  CheckReport? _report;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() => _running = true);
    final r = await context.read<BatchController>().runChecks();
    setState(() {
      _report = r;
      _running = false;
    });
  }

  Color _color(Severity s) => switch (s) {
        Severity.block => Colors.red.shade700,
        Severity.warning => Colors.orange.shade800,
        Severity.info => Colors.blueGrey,
      };

  IconData _icon(Severity s) => switch (s) {
        Severity.block => Icons.block,
        Severity.warning => Icons.warning_amber,
        Severity.info => Icons.info_outline,
      };

  @override
  Widget build(BuildContext context) {
    final c = context.watch<BatchController>();
    final b = c.batch!;
    final r = _report;
    return Scaffold(
      appBar: AppBar(
        title: const Text('核对与人工处置'),
        actions: [
          IconButton(onPressed: _run, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _running || r == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                _summaryCard(b, c),
                if (r.issues.isEmpty)
                  const Card(
                    child: ListTile(
                      leading: Icon(Icons.check_circle, color: Colors.green),
                      title: Text('未发现需要核对的问题'),
                      subtitle: Text('仍由收青员决定是否收青，系统不自动定级'),
                    ),
                  ),
                for (final i in r.issues) _issueTile(c, i),
                const SizedBox(height: 12),
                FilledButton.icon(
                  icon: const Icon(Icons.fact_check),
                  label: const Text('完成收青登记',
                      style: TextStyle(fontSize: 18)),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                    backgroundColor: Colors.green.shade800,
                  ),
                  onPressed: b.status == ReceiptStatus.finalized
                      ? null
                      : () => _finalize(c),
                ),
              ],
            ),
    );
  }

  Widget _summaryCard(ReceivingBatch b, BatchController c) {
    final open = c.openBlocks.length;
    return Card(
      color: open > 0 ? Colors.red.shade50 : Colors.green.shade50,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('净重合计 ${b.totalNetKg} kg（${b.weighings.length} 次称量相加）',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('鲜叶票 ${b.lots.length} 张 · 小样 ${b.samples.length} 份'
                ' · 照片 ${b.photos.length} 张'),
            Text('采后时长：${_range(b)}'),
            if (b.status == ReceiptStatus.finalized)
              Text('已收青，收青员：${b.finalizedBy}\n结论：${b.decisionNote}')
            else
              Text(open > 0 ? '尚有 $open 项需人工处置后才能收青' : '无待处置项，可由收青员收青'),
          ],
        ),
      ),
    );
  }

  String _range(ReceivingBatch b) {
    final r = b.postHarvestRange();
    if (r == null) return '—';
    return r.minHours == r.maxHours
        ? '${r.minHours}h'
        : '${r.minHours}~${r.maxHours}h';
  }

  Widget _issueTile(BatchController c, CheckIssue i) {
    final acked = c.isAcked(i);
    return Card(
      child: ListTile(
        leading: Icon(_icon(i.severity), color: _color(i.severity)),
        title: Text('[${i.severity.label}] ${i.code.label}'),
        subtitle: Text(i.message),
        trailing: acked
            ? const Icon(Icons.how_to_reg, color: Colors.green)
            : (i.severity == Severity.info
                ? null
                : TextButton(
                    onPressed: () => _ack(c, i),
                    child: const Text('人工处置'),
                  )),
      ),
    );
  }

  Future<void> _ack(BatchController c, CheckIssue i) async {
    final accepted = await showModalBottomSheet<bool>(
      context: context,
      builder: (_) => _AckSheet(issue: i),
    );
    if (accepted != null) setState(() {});
  }

  Future<void> _finalize(BatchController c) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('人工收青结论'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('系统不提供等级/价格；请填写处置与验收结论。',
                style: TextStyle(color: Colors.red.shade700)),
            const SizedBox(height: 8),
            TextField(
              controller: ctrl,
              maxLines: 3,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '如：篓底闷热小样已挑出，其余正常收青',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确认收青')),
        ],
      ),
    );
    if (ok != true || ctrl.text.trim().isEmpty) return;
    final r = await c.finalize(ctrl.text.trim());
    if (!mounted) return;
    if (r.ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已完成收青，记录保存在本机待同步')),
      );
      setState(() {});
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('还有未人工处置项：\n${r.openBlockKeys.join('\n')}'),
        backgroundColor: Colors.red,
      ));
    }
  }
}

class _AckSheet extends StatefulWidget {
  const _AckSheet({required this.issue});
  final CheckIssue issue;

  @override
  State<_AckSheet> createState() => _AckSheetState();
}

class _AckSheetState extends State<_AckSheet> {
  bool _accepted = false;
  final _note = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final i = widget.issue;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(i.code.label,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
          const SizedBox(height: 6),
          Text(i.message),
          const SizedBox(height: 12),
          RadioListTile<bool>(
            contentPadding: EdgeInsets.zero,
            title: const Text('已按提示纠正（如挑出问题小样/复称）'),
            value: false,
            groupValue: _accepted,
            onChanged: (v) => setState(() => _accepted = v!),
          ),
          RadioListTile<bool>(
            contentPadding: EdgeInsets.zero,
            title: const Text('知悉并接受现状，继续收青'),
            value: true,
            groupValue: _accepted,
            onChanged: (v) => setState(() => _accepted = v!),
          ),
          TextField(
            controller: _note,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: '处置说明（留存审计）',
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            style:
                FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: () async {
              if (_note.text.trim().isEmpty) return;
              await context.read<BatchController>().acknowledge(
                    i,
                    accepted: _accepted,
                    note: _note.text.trim(),
                  );
              if (context.mounted) Navigator.pop(context, true);
            },
            child: const Text('提交人工处置'),
          ),
        ],
      ),
    );
  }
}
