import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:tea_core/tea_core.dart';

import '../../app/batch_controller.dart';
import '../../services/scan_service.dart';

/// 扫码绑定竹篓与运输批；雨损/反光识别不了时手工录入或标记损坏重贴。
class BindBasketPage extends StatefulWidget {
  const BindBasketPage({super.key});

  @override
  State<BindBasketPage> createState() => _BindBasketPageState();
}

class _BindBasketPageState extends State<BindBasketPage> {
  late final MobileScannerController _scanner;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _scanner = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  }

  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture cap) async {
    if (_busy) return;
    final result = ScanService.fromBarcodeCapture(cap);
    if (result == null) return;
    _busy = true;
    try {
      switch (result) {
        case BasketScan(:final basketCode):
          await _bind(basketCode);
        case BatchScan():
          _snack('这是运输批码，请扫竹篓码');
        case UnrecognizedScan(:final raw):
          _snack('标签无法识别($raw)，请手工录入或标记雨损重贴');
      }
    } finally {
      await Future.delayed(const Duration(milliseconds: 900));
      _busy = false;
    }
  }

  Future<void> _bind(String code, {ContainerType? container}) async {
    final c = context.read<BatchController>();
    await c.bindBasket(code);
    if (container != null) {
      await c.registerBasketProfile(code, container, 0);
    }
    if (mounted) _snack('已绑定 $code');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<BatchController>();
    final b = c.batch!;
    return Scaffold(
      appBar: AppBar(title: const Text('扫码绑定竹篓')),
      body: Column(
        children: [
          SizedBox(
            height: 240,
            child: MobileScanner(
              controller: _scanner,
              onDetect: (cap) => _onDetect(cap),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.keyboard),
                    label: const Text('手工录入篓号'),
                    onPressed: _manualCode,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.water_drop, color: Colors.red),
                    label: const Text('标签雨损重贴'),
                    onPressed: _damageFlow,
                  ),
                ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: ListView(
              children: [
                for (final code in b.basketCodes)
                  ListTile(
                    leading: const Icon(Icons.inventory),
                    title: Text(code),
                    subtitle: Text(b.labelDamaged && code == b.damagedBasketCode
                        ? '雨损：${b.relabelNote}'
                        : '已绑定本批 ${b.code}'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _manualCode() async {
    final code = await _askText('竹篓编号（BK-站点-序号）');
    if (code != null && code.isNotEmpty) {
      await _bind(code);
    }
  }

  Future<void> _damageFlow() async {
    final oldCode = await _askText('受损标签上的旧篓号（可辨认部分）');
    if (oldCode == null || oldCode.isEmpty) return;
    final note = await _askText('雨损情况与人工核对说明') ?? '标签雨损';
    if (!mounted) return;
    final c = context.read<BatchController>();
    await c.reportLabelDamage(oldCode, note);
    final newCode = await _askText('补打重贴的新篓号');
    if (newCode != null && newCode.isNotEmpty && mounted) {
      await c.relabel(
        oldCode: oldCode,
        newCode: newCode,
        container: ContainerType.bambooBasket,
      );
      _snack('已重贴：$oldCode → $newCode，旧称量记录保留');
    }
  }

  Future<String?> _askText(String title) {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, ctrl.text.trim()),
              child: const Text('确定')),
        ],
      ),
    );
  }

  void _snack(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
    }
  }
}
