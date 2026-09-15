/// 相机接口：记录摊样照片、标签雨损照片、红变损伤照片。
///
/// 拍照后只在本地登记路径，断网照常；联网由 SyncService 上传后回填 remoteUrl。
library;

import 'dart:io';

import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tea_core/tea_core.dart';

class CameraService {
  CameraController? _controller;
  List<CameraDescription> _cameras = const [];

  Future<CameraController> start() async {
    _cameras = await availableCameras();
    final back = _cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => _cameras.first,
    );
    final c = CameraController(
      back,
      ResolutionPreset.high,
      enableAudio: false,
    );
    await c.initialize();
    _controller = c;
    return c;
  }

  CameraController? get controller => _controller;

  Future<void> dispose() async {
    await _controller?.dispose();
    _controller = null;
  }

  /// 拍一张照片并返回 LotPhoto（文件已落到应用文档目录）。
  Future<LotPhoto> takePhoto({
    required String batchId,
    required PhotoTag tag,
    String? lotId,
    String? basketCode,
  }) async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      throw StateError('相机未初始化，无法记录摊样照片');
    }
    // camera 0.11：takePicture() 返回临时 XFile，再复制到应用文档目录长期保存
    final shot = await c.takePicture();
    final dir = await getApplicationDocumentsDirectory();
    final photoDir = Directory('${dir.path}/tea_photos/$batchId');
    if (!photoDir.existsSync()) photoDir.createSync(recursive: true);
    final fname =
        '${tag.name}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final saved = await File(shot.path).copy('${photoDir.path}/$fname');
    return LotPhoto(
      id: 'PH-${DateTime.now().microsecondsSinceEpoch}',
      batchId: batchId,
      lotId: lotId,
      basketCode: basketCode,
      tag: tag,
      localPath: saved.path,
      takenAt: DateTime.now(),
    );
  }
}
