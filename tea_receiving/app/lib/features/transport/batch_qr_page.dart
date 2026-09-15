import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:tea_core/tea_core.dart';

import '../../app/batch_controller.dart';

/// 运输批二维码：贴在竹篓/车厢上，与竹篓码共同建立"篓 ↔ 运输批"绑定。
class BatchQrPage extends StatelessWidget {
  const BatchQrPage({super.key});

  @override
  Widget build(BuildContext context) {
    final b = context.watch<BatchController>().batch;
    if (b == null) {
      return const Scaffold(body: Center(child: Text('暂无批次')));
    }
    final serial = b.code.split('-').last;
    final qr = BatchQr(pointCode: b.pointId, serial: serial).encode();
    return Scaffold(
      appBar: AppBar(title: const Text('运输批二维码')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(b.code,
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            QrImageView(data: qr, size: 260),
            const SizedBox(height: 16),
            Text(qr, style: const TextStyle(color: Colors.black54)),
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                '扫码后把本批竹篓逐一绑定；标签雨损时可手工录入或补打重贴',
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
