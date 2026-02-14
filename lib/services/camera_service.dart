import 'dart:io';
import 'package:camera/camera.dart';

typedef ImageCallback = void Function(CameraImage image);

class CameraService {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isStreaming = false;

  CameraController? get controller => _controller;
  bool get isInitialized => _controller?.value.isInitialized ?? false;
  bool get isStreaming => _isStreaming;

  Future<void> initialize({
    CameraLensDirection lensDirection = CameraLensDirection.back,
    ResolutionPreset resolution = ResolutionPreset.medium,
  }) async {
    _cameras = await availableCameras();
    if (_cameras == null || _cameras!.isEmpty) {
      throw CameraException('NoCameras', 'No cameras available on device');
    }

    final CameraDescription camera = _cameras!.firstWhere(
      (cam) => cam.lensDirection == lensDirection,
      orElse: () => _cameras!.first,
    );

    final ImageFormatGroup imageFormat = Platform.isAndroid
        ? ImageFormatGroup.nv21
        : ImageFormatGroup.bgra8888;

    _controller = CameraController(
      camera,
      resolution,
      enableAudio: false,
      imageFormatGroup: imageFormat,
    );

    await _controller!.initialize();
  }

  Future<void> startImageStream(ImageCallback onImage) async {
    if (_controller == null || !isInitialized) {
      throw StateError('Camera not initialized');
    }
    if (_isStreaming) return;

    await _controller!.startImageStream(onImage);
    _isStreaming = true;
  }

  Future<void> stopImageStream() async {
    if (!_isStreaming || _controller == null) return;

    await _controller!.stopImageStream();
    _isStreaming = false;
  }

  CameraDescription? get currentCamera {
    if (_cameras == null || _cameras!.isEmpty) return null;
    if (_controller == null) return null;

    return _cameras!.firstWhere(
      (cam) => cam.lensDirection == _controller!.description.lensDirection,
      orElse: () => _cameras!.first,
    );
  }

  Future<void> dispose() async {
    await stopImageStream();
    await _controller?.dispose();
    _controller = null;
    _cameras = null;
  }
}
