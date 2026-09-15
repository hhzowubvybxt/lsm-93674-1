import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:tea_core/tea_core.dart';

import '../../services/camera_service.dart';

/// 相机接口页：拍摊样照片 / 标签雨损照片 / 红变部位照片。
class CameraPage extends StatefulWidget {
  const CameraPage({
    super.key,
    required this.batchId,
    required this.tag,
    this.lotId,
    this.basketCode,
  });

  final String batchId;
  final PhotoTag tag;
  final String? lotId;
  final String? basketCode;

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> {
  final _svc = CameraService();
  CameraController? _c;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _svc.start().then((c) => setState(() => _c = c)).catchError((Object e) {
      setState(() => _error = '$e');
    });
  }

  @override
  void dispose() {
    _svc.dispose();
    super.dispose();
  }

  Future<void> _capture() async {
    if (_busy) return;
    _busy = true;
    try {
      final photo = await _svc.takePhoto(
        batchId: widget.batchId,
        tag: widget.tag,
        lotId: widget.lotId,
        basketCode: widget.basketCode,
      );
      if (mounted) Navigator.of(context).pop(photo);
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('拍照失败：$e')));
      }
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('记录${widget.tag.label}')),
      body: _error != null
          ? Center(child: Text('相机不可用：$_error'))
          : _c == null
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    Expanded(
                        child: Center(
                            child: CameraPreview(_c!))),
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: FloatingActionButton.extended(
                          onPressed: _capture,
                          icon: const Icon(Icons.camera_alt, size: 30),
                          label: const Text('拍照留证',
                              style: TextStyle(fontSize: 18)),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}
