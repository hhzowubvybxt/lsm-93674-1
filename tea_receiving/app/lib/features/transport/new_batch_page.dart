import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tea_core/tea_core.dart';

import '../../app/batch_controller.dart';

/// 到场登记：运输批 + 一张或多张鲜叶票（多茶园混装）。
class NewBatchPage extends StatefulWidget {
  const NewBatchPage({super.key});

  @override
  State<NewBatchPage> createState() => _NewBatchPageState();
}

class _LotDraft {
  String blockId = '';
  PickingMethod method = PickingMethod.handOneBudOneLeaf;
  DateTime pickStart = DateTime.now().subtract(const Duration(hours: 4));
  DateTime pickEnd = DateTime.now().subtract(const Duration(hours: 4));
}

class _NewBatchPageState extends State<NewBatchPage> {
  DateTime _arrived = DateTime.now();
  bool _spreadFirst = false;
  DateTime? _spreadAt;
  final List<_LotDraft> _lots = [_LotDraft()];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('新运输批登记')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _DateTimeTile(
            label: '到场时间',
            value: _arrived,
            onPick: (d) => setState(() => _arrived = d),
          ),
          SwitchListTile(
            title: const Text('到场后先摊开，稍后再登记'),
            subtitle: const Text('允许：采后时长以到场时间为准'),
            value: _spreadFirst,
            onChanged: (v) => setState(() {
              _spreadFirst = v;
              _spreadAt = v ? _arrived : null;
            }),
          ),
          if (_spreadFirst)
            _DateTimeTile(
              label: '开始摊放时间',
              value: _spreadAt ?? _arrived,
              onPick: (d) => setState(() => _spreadAt = d),
            ),
          const Divider(height: 32),
          Text('鲜叶票（多个茶园混装请逐张添加，分别保留事实）',
              style: Theme.of(context).textTheme.titleMedium),
          for (var i = 0; i < _lots.length; i++) _lotCard(i),
          TextButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('再加一张鲜叶票（另一茶园）'),
            onPressed: () => setState(() => _lots.add(_LotDraft())),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            icon: const Icon(Icons.check),
            label: const Text('登记并进入收青',
                style: TextStyle(fontSize: 18)),
            style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56)),
            onPressed: _submit,
          ),
        ],
      ),
    );
  }

  Widget _lotCard(int i) {
    final lot = _lots[i];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('鲜叶票 ${i + 1}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                if (_lots.length > 1)
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => setState(() => _lots.removeAt(i)),
                  ),
              ],
            ),
            TextFormField(
              decoration: const InputDecoration(
                  labelText: '茶园区块编号（如 BLK-A12）'),
              initialValue: lot.blockId,
              onChanged: (v) => lot.blockId = v.trim(),
            ),
            DropdownButtonFormField<PickingMethod>(
              value: lot.method,
              decoration: const InputDecoration(labelText: '采法'),
              items: [
                for (final m in PickingMethod.values)
                  DropdownMenuItem(value: m, child: Text(m.label)),
              ],
              onChanged: (v) => setState(() => lot.method = v!),
            ),
            const SizedBox(height: 8),
            const Text('采摘时间（只记得区间时分别选起止）'),
            Row(
              children: [
                Expanded(
                  child: _DateTimeTile(
                    compact: true,
                    label: '起',
                    value: lot.pickStart,
                    onPick: (d) => setState(() => lot.pickStart = d),
                  ),
                ),
                Expanded(
                  child: _DateTimeTile(
                    compact: true,
                    label: '止',
                    value: lot.pickEnd,
                    onPick: (d) => setState(() => lot.pickEnd = d),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (_lots.any((l) => l.blockId.isEmpty)) {
      _snack('每张鲜叶票都要填茶园区块编号');
      return;
    }
    for (final l in _lots) {
      if (l.pickEnd.isBefore(l.pickStart)) {
        _snack('采摘止时间不能早于起时间');
        return;
      }
    }
    final c = context.read<BatchController>();
    await c.startBatch(
      arrivedAt: _arrived,
      alreadySpread: _spreadFirst,
      spreadAt: _spreadAt,
      // 先摊后登记时此刻不登记：收青员摊放、清点后在批次页"补登记"
      registeredAt: _spreadFirst ? null : DateTime.now(),
    );
    for (final l in _lots) {
      await c.addLot(
        blockId: l.blockId,
        method: l.method,
        pickStart: l.pickStart,
        pickEnd: l.pickEnd,
      );
    }
    if (mounted) Navigator.of(context).pop();
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
}

class _DateTimeTile extends StatelessWidget {
  const _DateTimeTile({
    required this.label,
    required this.value,
    required this.onPick,
    this.compact = false,
  });

  final String label;
  final DateTime value;
  final ValueChanged<DateTime> onPick;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final text =
        '${value.year}-${pad2(value.month)}-${pad2(value.day)} ${pad2(value.hour)}:${pad2(value.minute)}';
    final child = ListTile(
      contentPadding: compact ? EdgeInsets.zero : null,
      title: Text(label),
      subtitle: Text(text, style: const TextStyle(fontSize: 16)),
      trailing: const Icon(Icons.edit_calendar),
      onTap: () async {
        final d = await showDatePicker(
          context: context,
          initialDate: value,
          firstDate: DateTime(2026),
          lastDate: DateTime(2027),
        );
        if (d == null || !context.mounted) return;
        final t = await showTimePicker(
            context: context,
            initialTime: TimeOfDay.fromDateTime(value));
        if (t == null) return;
        onPick(DateTime(d.year, d.month, d.day, t.hour, t.minute));
      },
    );
    return child;
  }

  static String pad2(int v) => v.toString().padLeft(2, '0');
}
