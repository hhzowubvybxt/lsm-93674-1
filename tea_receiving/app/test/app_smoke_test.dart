// 不依赖真机/Isar：直接验证首页的护栏文案与大按钮存在。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:isar/isar.dart';
import 'package:tea_receiving/app/batch_controller.dart';
import 'package:tea_receiving/features/home/home_page.dart';
import 'package:tea_receiving/services/sync_service.dart';

class _FakeIsar implements Isar {
  @override
  dynamic noSuchMethod(Invocation i) {
    if (i.isGetter) return null;
    return Future<void>.value();
  }
}

void main() {
  testWidgets('收青点六枚大按钮可见；无批次时点绑篓给出提示', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fakeIsar = _FakeIsar();
    final c = BatchController(
      isar: fakeIsar,
      pointCode: 'P01',
      operator: '测试员',
    );
    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider<SyncService>.value(
            value: SyncService(isar: fakeIsar, api: NullReceivingApi())),
        ChangeNotifierProvider<BatchController>.value(value: c),
      ],
      child: const MaterialApp(home: HomePage()),
    ));
    await tester.pump();

    expect(find.textContaining('新运输批'), findsWidgets);
    expect(find.textContaining('扫码绑竹篓'), findsOneWidget);
    expect(find.textContaining('过秤称重'), findsOneWidget);
    expect(find.textContaining('随机抽样'), findsOneWidget);
    expect(find.textContaining('核对处置'), findsOneWidget);
    expect(find.textContaining('收青记录'), findsOneWidget);
    expect(find.textContaining('等级与价格由人工决定'), findsOneWidget);

    await tester.tap(find.textContaining('扫码绑竹篓'));
    await tester.pump();
    expect(find.textContaining('请先点'), findsOneWidget);
  });
}
