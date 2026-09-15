import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:tea_core/tea_core.dart';

import '../../app/batch_controller.dart';

/// 过秤称重：一只竹篓可分多次称量，净重逐次相加。
class WeighPage extends StatefulWidget {
  const WeighPage({super.key});

  @override
  State<WeighPage> createState() => _WeighPageState();
}

class _WeighPageState extends State<WeighPage> {
  String? _basket;
  final _gross = TextEditingController();
  final _tare = TextEditingController(text: '0.4');
  bool _split = false;
  int _splitPart = 2;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<BatchController>();
    final b = c.batch!;
    _basket ??= b.basketCodes.isEmpty ? null : b.basketCodes.last;
    return Scaffold(
      appBar: AppBar(title: const Text('过秤称重')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<String>(
            value: _basket,
            decoration: const InputDecoration(labelText: '竹篓'),
            items: [
              for (final code in b.basketCodes)
                DropdownMenuItem(value: code, child: Text(code)),
            ],
            onChanged: (v) => setState(() => _basket = v),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _gross,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
                  ],
                  decoration: const InputDecoration(
                      labelText: '毛重 kg', border: OutlineInputBorder()),
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _tare,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: '皮重 kg', border: OutlineInputBorder()),
                ),
              ),
            ],
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('本篓分次称量（倒一部分上秤）'),
            subtitle: Text(_split ? '第 $_splitPart 次' : '第一次整篓'),
            value: _split,
            onChanged: (v) => setState(() => _split = v ?? false),
          ),
          if (_split)
            Slider(
              max: 6,
              min: 2,
              divisions: 4,
              label: '第 $_splitPart 次',
              value: _splitPart.toDouble(),
              onChanged: (v) => setState(() => _splitPart = v.round()),
            ),
          FilledButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('记录本次称量', style: TextStyle(fontSize: 18)),
            style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(54)),
            onPressed: _submit,
          ),
          const SizedBox(height: 20),
          Card(
            color: Colors.green.shade50,
            child: ListTile(
              title: const Text('净重合计（逐次相加，不做大批平均）',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('毛重 ${b.totalGrossKg}kg · 皮重 '
                  '${b.totalTareKg}kg'),
              trailing: Text('${b.totalNetKg} kg',
                  style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.green)),
            ),
          ),
          for (final entry in b.netByBasket.entries)
            ListTile(
              dense: true,
              leading: const Icon(Icons.inventory_2, size: 20),
              title: Text(entry.key),
              trailing: Text('${entry.value} kg'),
            ),
          const Divider(),
          for (final w in b.weighings.reversed)
            ListTile(
              dense: true,
              leading: Icon(w.splitPart > 1 ? Icons.content_cut : Icons.scale,
                  size: 20),
              title: Text('${w.basketCode} · 毛 ${w.grossKg} - 皮 ${w.tareKg}'
                  ' = 净 ${w.netKg} kg'),
              subtitle: Text(w.splitPart > 1 ? '分称第 ${w.splitPart} 次' : '整篓称量'),
            ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final code = _basket;
    final gross = double.tryParse(_gross.text);
    final tare = double.tryParse(_tare.text) ?? 0;
    if (code == null) {
      _snack('请先扫码绑定竹篓');
      return;
    }
    if (gross == null || gross <= 0) {
      _snack('毛重必须是正数');
      return;
    }
    if (tare < 0 || tare > gross) {
      _snack('皮重应在 0 与毛重之间');
      return;
    }
    try {
      await context.read<BatchController>().addWeighing(
            basketCode: code,
            grossKg: gross,
            tareKg: tare,
            at: DateTime.now(),
            splitPart: _split ? _splitPart : 1,
          );
      _gross.clear();
    } on ReceivingStateError catch (e) {
      _snack(e.message);
    }
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
}
