import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class TextRecognitionService {
  TextRecognizer? _recognizer;
  TextRecognitionScript _currentScript = TextRecognitionScript.latin;

  TextRecognitionScript get currentScript => _currentScript;

  void initialize({TextRecognitionScript script = TextRecognitionScript.latin}) {
    _currentScript = script;
    _recognizer?.close();
    _recognizer = TextRecognizer(script: script);
  }

  void setScript(TextRecognitionScript script) {
    if (script == _currentScript && _recognizer != null) return;
    initialize(script: script);
  }

  Future<RecognizedText?> processImage(InputImage inputImage) async {
    if (_recognizer == null) {
      initialize();
    }

    try {
      return await _recognizer!.processImage(inputImage);
    } catch (e) {
      debugPrint('Text recognition error: $e');
      return null;
    }
  }

  Future<String?> recognizeText(InputImage inputImage) async {
    final result = await processImage(inputImage);
    return result?.text;
  }

  Future<void> dispose() async {
    await _recognizer?.close();
    _recognizer = null;
  }
}
