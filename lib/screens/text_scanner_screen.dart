import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:permission_handler/permission_handler.dart';

class TextScannerScreen extends StatefulWidget {
  const TextScannerScreen({super.key});

  @override
  State<TextScannerScreen> createState() => _TextScannerScreenState();
}

class _TextScannerScreenState extends State<TextScannerScreen>
    with WidgetsBindingObserver {
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  TextRecognizer? _textRecognizer;

  bool _isProcessing = false;
  DateTime? _lastProcessTime;
  static const Duration _minProcessInterval = Duration(milliseconds: 500);

  bool _isScanning = true;
  RecognizedText? _recognizedText;
  bool _isInitializing = true;
  String? _errorMessage;
  TextRecognitionScript _selectedScript = TextRecognitionScript.japanese;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraController?.dispose();
    _textRecognizer?.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;

    if (state == AppLifecycleState.inactive) {
      controller.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  Future<void> _initializeCamera() async {
    setState(() {
      _isInitializing = true;
      _errorMessage = null;
    });

    try {
      final status = await Permission.camera.request();
      if (!status.isGranted) {
        throw Exception('カメラ権限が許可されていません');
      }

      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        throw Exception('カメラが見つかりません');
      }

      final camera = _cameras!.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras!.first,
      );

      _cameraController = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.nv21,
      );

      await _cameraController!.initialize();

      _textRecognizer?.close();
      _textRecognizer = TextRecognizer(script: _selectedScript);

      if (mounted) {
        await _cameraController!.startImageStream(_processImage);
        setState(() {
          _isInitializing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isInitializing = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  void _processImage(CameraImage image) async {
    if (!_isScanning) return;
    if (_isProcessing) return;
    if (_textRecognizer == null) return;

    final now = DateTime.now();
    if (_lastProcessTime != null &&
        now.difference(_lastProcessTime!) < _minProcessInterval) {
      return;
    }

    _isProcessing = true;
    _lastProcessTime = now;

    try {
      final camera = _cameras?.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras!.first,
      );
      if (camera == null) return;

      final inputImage = _convertToInputImage(image, camera);
      if (inputImage == null) {
        debugPrint('Failed to convert image');
        return;
      }

      final result = await _textRecognizer!.processImage(inputImage);

      if (mounted) {
        setState(() {
          _recognizedText = result;
        });
      }
    } catch (e) {
      debugPrint('Text recognition error: $e');
    } finally {
      _isProcessing = false;
    }
  }

  InputImage? _convertToInputImage(CameraImage image, CameraDescription camera) {
    final sensorOrientation = camera.sensorOrientation;
    final rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    if (rotation == null) return null;

    // Handle NV21 format (most Android cameras)
    // NV21: Y plane first, then interleaved VU
    if (image.format.group == ImageFormatGroup.nv21) {
      final bytes = image.planes.first.bytes;

      return InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: InputImageFormat.nv21,
          bytesPerRow: image.planes.first.bytesPerRow,
        ),
      );
    }

    // Handle YUV420 format
    if (image.format.group == ImageFormatGroup.yuv420) {
      final yPlane = image.planes[0];
      final uPlane = image.planes[1];
      final vPlane = image.planes[2];

      final yBytes = yPlane.bytes;
      final uBytes = uPlane.bytes;
      final vBytes = vPlane.bytes;

      // Convert YUV420 to NV21 format
      final nv21Bytes = _yuv420ToNv21(
        yBytes, uBytes, vBytes,
        image.width, image.height,
        yPlane.bytesPerRow,
        uPlane.bytesPerRow,
        uPlane.bytesPerPixel ?? 1,
      );

      return InputImage.fromBytes(
        bytes: nv21Bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: InputImageFormat.nv21,
          bytesPerRow: image.width,
        ),
      );
    }

    return null;
  }

  Uint8List _yuv420ToNv21(
    Uint8List yBytes,
    Uint8List uBytes,
    Uint8List vBytes,
    int width,
    int height,
    int yRowStride,
    int uvRowStride,
    int uvPixelStride,
  ) {
    final int ySize = width * height;
    final int uvSize = width * height ~/ 2;
    final nv21 = Uint8List(ySize + uvSize);

    // Copy Y plane
    int yIndex = 0;
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        nv21[yIndex++] = yBytes[y * yRowStride + x];
      }
    }

    // Interleave V and U (NV21 is VUVU, not UVUV)
    int uvIndex = ySize;
    final int uvHeight = height ~/ 2;
    final int uvWidth = width ~/ 2;

    for (int y = 0; y < uvHeight; y++) {
      for (int x = 0; x < uvWidth; x++) {
        final int uvOffset = y * uvRowStride + x * uvPixelStride;
        nv21[uvIndex++] = vBytes[uvOffset]; // V
        nv21[uvIndex++] = uBytes[uvOffset]; // U
      }
    }

    return nv21;
  }

  void _onScriptChanged(TextRecognitionScript? script) async {
    if (script == null || script == _selectedScript) return;

    setState(() {
      _selectedScript = script;
      _recognizedText = null;
    });

    _textRecognizer?.close();
    _textRecognizer = TextRecognizer(script: script);
  }

  void _toggleScanning() {
    setState(() {
      _isScanning = !_isScanning;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Text Scanner'),
        actions: [
          PopupMenuButton<TextRecognitionScript>(
            icon: const Icon(Icons.language),
            tooltip: 'Select Language',
            onSelected: _onScriptChanged,
            itemBuilder: (context) => TextRecognitionScript.values.map((script) {
              return PopupMenuItem(
                value: script,
                child: Row(
                  children: [
                    if (script == _selectedScript)
                      const Icon(Icons.check, size: 18)
                    else
                      const SizedBox(width: 18),
                    const SizedBox(width: 8),
                    Text(_getScriptName(script)),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  String _getScriptName(TextRecognitionScript script) {
    switch (script) {
      case TextRecognitionScript.latin:
        return 'Latin';
      case TextRecognitionScript.chinese:
        return 'Chinese';
      case TextRecognitionScript.japanese:
        return 'Japanese';
      case TextRecognitionScript.korean:
        return 'Korean';
      default:
        return script.name;
    }
  }

  Widget _buildBody() {
    if (_isInitializing) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('カメラを初期化中...'),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(_errorMessage!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _initializeCamera,
                child: const Text('再試行'),
              ),
            ],
          ),
        ),
      );
    }

    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      return const Center(child: Text('カメラが利用できません'));
    }

    return Column(
      children: [
        Expanded(
          flex: 1,
          child: _buildCameraPreview(controller),
        ),
        Expanded(
          flex: 1,
          child: _buildTextDisplay(),
        ),
        _buildControlBar(),
      ],
    );
  }

  Widget _buildControlBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: Colors.grey[200],
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _toggleScanning,
            icon: Icon(_isScanning ? Icons.stop : Icons.play_arrow),
            label: Text(_isScanning ? '停止' : '開始'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _isScanning ? Colors.red : Colors.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCameraPreview(CameraController controller) {
    return Container(
      color: Colors.black,
      child: Center(
        child: AspectRatio(
          aspectRatio: 1 / controller.value.aspectRatio,
          child: CameraPreview(controller),
        ),
      ),
    );
  }

  Widget _buildTextDisplay() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      color: Colors.grey[100],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.text_fields, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '認識テキスト (${_getScriptName(_selectedScript)})',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (_recognizedText != null)
                Text(
                  '${_recognizedText!.blocks.length} blocks',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
          const Divider(),
          Expanded(
            child: SingleChildScrollView(
              child: _buildRecognizedText(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecognizedText() {
    if (_recognizedText == null || _recognizedText!.blocks.isEmpty) {
      return Text(
        'カメラをテキストに向けてください...',
        style: TextStyle(
          fontSize: 16,
          color: Colors.grey[600],
          fontStyle: FontStyle.italic,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Full text
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.blue[50],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('【Full Text】', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              const SizedBox(height: 4),
              Text(_recognizedText!.text, style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),

        // Blocks
        for (int blockIndex = 0; blockIndex < _recognizedText!.blocks.length; blockIndex++)
          _buildBlockWidget(_recognizedText!.blocks[blockIndex], blockIndex),
      ],
    );
  }

  Widget _buildBlockWidget(TextBlock block, int blockIndex) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Block header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.green[100],
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text('Block $blockIndex', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
          ),
          const SizedBox(height: 6),

          // Block text
          Text(block.text, style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 6),

          // Block properties
          _buildPropertyRow('boundingBox', _formatRect(block.boundingBox)),
          _buildPropertyRow('cornerPoints', _formatCornerPoints(block.cornerPoints)),
          _buildPropertyRow('recognizedLanguages', block.recognizedLanguages.join(', ')),

          const Divider(height: 12),

          // Lines
          for (int lineIndex = 0; lineIndex < block.lines.length; lineIndex++)
            _buildLineWidget(block.lines[lineIndex], lineIndex),
        ],
      ),
    );
  }

  Widget _buildLineWidget(TextLine line, int lineIndex) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.orange[50],
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Line header
          Text('  Line $lineIndex', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Colors.orange[800])),
          const SizedBox(height: 4),

          // Line text
          Text('  "${line.text}"', style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 4),

          // Line properties
          _buildPropertyRow('  boundingBox', _formatRect(line.boundingBox)),
          _buildPropertyRow('  cornerPoints', _formatCornerPoints(line.cornerPoints)),
          _buildPropertyRow('  confidence', line.confidence?.toStringAsFixed(3) ?? 'null'),
          _buildPropertyRow('  angle', line.angle?.toStringAsFixed(2) ?? 'null'),
          _buildPropertyRow('  recognizedLanguages', line.recognizedLanguages.join(', ')),

          const SizedBox(height: 4),

          // Elements
          for (int elemIndex = 0; elemIndex < line.elements.length; elemIndex++)
            _buildElementWidget(line.elements[elemIndex], elemIndex),
        ],
      ),
    );
  }

  Widget _buildElementWidget(TextElement element, int elemIndex) {
    return Container(
      margin: const EdgeInsets.only(left: 8, bottom: 4),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.purple[50],
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('    Element $elemIndex: "${element.text}"',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.purple[800])),
          _buildPropertyRow('    boundingBox', _formatRect(element.boundingBox)),
          _buildPropertyRow('    cornerPoints', _formatCornerPoints(element.cornerPoints)),
          _buildPropertyRow('    confidence', element.confidence?.toStringAsFixed(3) ?? 'null'),
          _buildPropertyRow('    angle', element.angle?.toStringAsFixed(2) ?? 'null'),
          _buildPropertyRow('    recognizedLanguages', element.recognizedLanguages.join(', ')),
        ],
      ),
    );
  }

  Widget _buildPropertyRow(String name, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$name: ', style: TextStyle(fontSize: 9, color: Colors.grey[600])),
          Expanded(
            child: Text(value.isEmpty ? '(empty)' : value,
                style: TextStyle(fontSize: 9, color: Colors.grey[800])),
          ),
        ],
      ),
    );
  }

  String _formatRect(Rect? rect) {
    if (rect == null) return 'null';
    return 'Rect(L:${rect.left.toInt()}, T:${rect.top.toInt()}, R:${rect.right.toInt()}, B:${rect.bottom.toInt()})';
  }

  String _formatCornerPoints(List<Point<int>> points) {
    if (points.isEmpty) return '[]';
    return points.map((p) => '(${p.x},${p.y})').join(', ');
  }
}
