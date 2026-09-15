import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tea_core/tea_core.dart';

import '../../app/batch_controller.dart';
import 'camera_page.dart';
import 'sample_entry_page.dart';

/// 随机抽样：按计划逐点抽取登记，并为每个小样拍摊样照片。
class SamplingPage extends StatefulWidget {
  const SamplingPage({super.key});

  @override
  State<SamplingPage> createState() => _SamplingPageState();
}

class _SamplingPageState extends State<SamplingPage> {
  SamplingPlan? _plan;
  int _count = 5;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<BatchController>();
    final b = c.batch!;
    _plan ??= c.buildPlan(_count);
    final plan = _plan!;
    return Scaffold(
      appBar: AppBar(title: const Text('随机抽样')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: Colors.amber.shade50,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      b.spreadStartedAt != null
                          ? '已先摊开：随机点落在摊放匾/边缘/中心'
                          : '未摊开：计划强制覆盖篓底与中层（闷热常藏于此）',
                    ),
                  ),
                  SizedBox(
                    width: 90,
                    child: DropdownButtonFormField<int>(
                      value: _count,
                      items: [
                        for (var n = 5; n <= 12; n++)
                          DropdownMenuItem(value: n, child: Text('$n 份')),
                      ],
                      onChanged: (v) => setState(() {
                        _count = v ?? 5;
                        _plan = null;
                      }),
                    ),
                  ),
                ],
              ),
            ),
          ),
          for (var i = 0; i < plan.points.length; i++)
            _pointTile(c, plan.points[i], i),
          const Divider(),
          Text('已登记小样 ${b.samples.length} 份',
              style: Theme.of(context).textTheme.titleMedium),
          for (final s in b.samples)
            ListTile(
              dense: true,
              leading: Icon(
                s.hotSpot || s.red.order >= RedDamageLevel.local.order
                    ? Icons.local_fire_department
                    : Icons.science,
                color: s.hotSpot ? Colors.red : null,
              ),
              title: Text('${s.position.label} · ${s.water.label}'
                  '${s.hasRealOffOdor ? " · 异味" : ""}'
                  '${s.red != RedDamageLevel.none ? " · ${s.red.label}" : ""}'),
              subtitle: Text(s.gradeShares
                  .map((g) => '${g.name} ${g.percent.round()}%')
                  .join('，')),
            ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.photo_camera),
            label: const Text('拍整体摊样照片'),
            onPressed: () => _takeSpreadPhoto(c),
          ),
        ],
      ),
    );
  }

  Widget _pointTile(BatchController c, SamplePoint p, int index) {
    final filled = c.batch!.samples.length > index;
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: filled ? Colors.green : Colors.teal,
          child: Text('${index + 1}'),
        ),
        title: Text('${p.position.label}（鲜叶票 ${p.lotId}）'),
        subtitle: Text('随机点 (${p.x}, ${p.y})'),
        trailing: filled
            ? const Icon(Icons.check_circle, color: Colors.green)
            : const Icon(Icons.chevron_right),
        onTap: filled
            ? null
            : () async {
                await Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => SampleEntryPage(point: p),
                ));
                setState(() {});
              },
      ),
    );
  }

  Future<void> _takeSpreadPhoto(BatchController c) async {
    final b = c.batch!;
    final photo = await Navigator.of(context).push<LotPhoto>(MaterialPageRoute(
      builder: (_) => CameraPage(batchId: b.id, tag: PhotoTag.spreadSample),
    ));
    if (photo != null) {
      await c.addPhoto(photo);
    }
  }
}
