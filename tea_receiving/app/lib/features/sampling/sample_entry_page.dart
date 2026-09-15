import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tea_core/tea_core.dart';

import '../../app/batch_controller.dart';

/// 小样登记：芽叶级配（行内百分比）、表面水、异味、红变、损伤、闷热。
class SampleEntryPage extends StatefulWidget {
  const SampleEntryPage({super.key, required this.point});

  final SamplePoint point;

  @override
  State<SampleEntryPage> createState() => _SampleEntryPageState();
}

class _ShareRow {
  _ShareRow(this.name, this.pct);
  String name;
  double pct;
}

class _SampleEntryPageState extends State<SampleEntryPage> {
  final List<_ShareRow> _shares = [
    _ShareRow('单芽', 60),
    _ShareRow('一芽一叶', 30),
    _ShareRow('单片', 10),
  ];
  SamplePosition? _actualPos;
  SurfaceWater _water = SurfaceWater.none;
  final Set<OffOdorType> _odors = {OffOdorType.none};
  RedDamageLevel _red = RedDamageLevel.none;
  BruiseLevel _bruise = BruiseLevel.none;
  bool _hotSpot = false;

  @override
  Widget build(BuildContext context) {
    final sum = _shares.fold<double>(0, (a, s) => a + s.pct);
    final ok = (sum - 100).abs() <= 2;
    return Scaffold(
      appBar: AppBar(
        title: const Text('登记小样'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: Colors.teal.shade50,
            child: ListTile(
              leading: const Icon(Icons.location_searching),
              title: Text('随机位置：${widget.point.position.label} '
                  '(${widget.point.x},${widget.point.y})'),
              subtitle: const Text('请按系统给点抽样，不要只挑篓面'),
            ),
          ),
          DropdownButtonFormField<SamplePosition>(
            value:
                _actualPos ?? widget.point.position,
            decoration: const InputDecoration(labelText: '实际抽取位置'),
            items: [
              for (final p in SamplePosition.values)
                DropdownMenuItem(value: p, child: Text(p.label)),
            ],
            onChanged: (v) => setState(() => _actualPos = v),
          ),
          const SizedBox(height: 16),
          Text('芽叶级配（各组分合计约 100%）',
              style: Theme.of(context).textTheme.titleSmall),
          for (var i = 0; i < _shares.length; i++) _shareRow(i),
          Text('合计 ${sum.toStringAsFixed(0)}%',
              style: TextStyle(
                  color: ok ? Colors.green : Colors.red,
                  fontWeight: FontWeight.bold)),
          if (!ok) const Text('合计应在 98%~102% 之间',
              style: TextStyle(color: Colors.red)),
          const Divider(height: 32),
          _labeledDropdown<SurfaceWater>(
            '表面水',
            _water,
            SurfaceWater.values,
            (v) => v.label,
            (v) => setState(() => _water = v!),
          ),
          const SizedBox(height: 8),
          Text('异味（可多选）',
              style: Theme.of(context).textTheme.titleSmall),
          Wrap(
            spacing: 8,
            children: [
              for (final o in OffOdorType.values)
                FilterChip(
                  label: Text(o.label),
                  selected: _odors.contains(o),
                  onSelected: (v) => setState(() {
                    if (o == OffOdorType.none) {
                      _odors
                        ..clear()
                        ..add(OffOdorType.none);
                    } else {
                      _odors.remove(OffOdorType.none);
                      v ? _odors.add(o) : _odors.remove(o);
                      if (_odors.isEmpty) _odors.add(OffOdorType.none);
                    }
                  }),
                ),
            ],
          ),
          const SizedBox(height: 8),
          _labeledDropdown<RedDamageLevel>(
            '红变',
            _red,
            RedDamageLevel.values,
            (v) => v.label,
            (v) => setState(() => _red = v!),
          ),
          _labeledDropdown<BruiseLevel>(
            '机械伤',
            _bruise,
            BruiseLevel.values,
            (v) => v.label,
            (v) => setState(() => _bruise = v!),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('该位置局部闷热（发热/水汽重）'),
            subtitle: const Text('只记录事实，不并入大批平均'),
            value: _hotSpot,
            onChanged: (v) => setState(() => _hotSpot = v),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.save),
            label: const Text('保存小样', style: TextStyle(fontSize: 17)),
            style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52)),
            onPressed: ok ? _save : null,
          ),
        ],
      ),
    );
  }

  Widget _shareRow(int i) {
    final r = _shares[i];
    return Row(
      children: [
        Expanded(
          child: TextFormField(
            initialValue: r.name,
            decoration: const InputDecoration(labelText: '组分'),
            onChanged: (v) => r.name = v,
          ),
        ),
        SizedBox(
          width: 110,
          child: Slider(
            value: r.pct,
            max: 100,
            divisions: 100,
            label: '${r.pct.round()}%',
            onChanged: (v) => setState(() => r.pct = v.roundToDouble()),
          ),
        ),
        SizedBox(
          width: 52,
          child: Text('${r.pct.round()}%'),
        ),
      ],
    );
  }

  Widget _labeledDropdown<T>(
    String label,
    T value,
    List<T> values,
    String Function(T) labelOf,
    ValueChanged<T?> onChanged,
  ) {
    return DropdownButtonFormField<T>(
      value: value,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final v in values)
          DropdownMenuItem(value: v, child: Text(labelOf(v))),
      ],
      onChanged: onChanged,
    );
  }

  Future<void> _save() async {
    final shares = _shares
        .where((r) => r.name.isNotEmpty)
        .map((r) => GradeShare(name: r.name, percent: r.pct))
        .toList();
    try {
      validateGradeShares(shares);
    } on ArgumentError catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message.toString())));
      return;
    }
    await context.read<BatchController>().addSample(
          point: widget.point,
          actualPosition: _actualPos ?? widget.point.position,
          grades: shares,
          water: _water,
          odors: _odors.toList(),
          red: _red,
          bruise: _bruise,
          hotSpot: _hotSpot,
        );
    if (mounted) Navigator.pop(context);
  }
}
