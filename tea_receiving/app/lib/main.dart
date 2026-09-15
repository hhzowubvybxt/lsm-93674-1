/// 鲜叶收青 App 入口。
///
/// 茶园区块 / 采法 / 采摘时间区间 / 运输容器 / 芽叶组成 / 红变损伤逐项保留；
/// 收青点用大按钮完成：建批 → 绑篓 → 称重 → 抽样 → 人工核对 → 收青。
/// 离线数据全部在 Isar，系统不自动定级定价。
library;

import 'package:flutter/material.dart';
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import 'app/batch_controller.dart';
import 'db/collections.dart';
import 'features/home/home_page.dart';
import 'services/sync_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dir = await getApplicationDocumentsDirectory();
  final isar = await Isar.open(
    [
      BatchRecordSchema,
      BasketRecordSchema,
      BlockRecordSchema,
      SyncQueueRecordSchema,
      PhotoRecordSchema,
    ],
    directory: dir.path,
  );
  runApp(TeaReceivingApp(isar: isar));
}

class TeaReceivingApp extends StatelessWidget {
  const TeaReceivingApp({super.key, required this.isar});

  final Isar isar;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<Isar>.value(value: isar),
        Provider<SyncService>(
          create: (_) =>
              SyncService(isar: isar, api: NullReceivingApi()),
        ),
        ChangeNotifierProvider<BatchController>(
          create: (_) => BatchController(
            isar: isar,
            pointCode: 'P01',
            operator: '当班收青员',
          ),
        ),
      ],
      child: MaterialApp(
        title: '鲜叶收青',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2E7D32)),
          useMaterial3: true,
        ),
        home: const HomePage(),
      ),
    );
  }
}
