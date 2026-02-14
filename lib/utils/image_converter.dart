import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class ImageConverter {
  static const Map<DeviceOrientation, int> _orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  static InputImage? convertCameraImage(
    CameraImage image,
    CameraDescription camera,
    DeviceOrientation deviceOrientation,
  ) {
    final InputImageRotation? rotation = _getImageRotation(
      camera,
      deviceOrientation,
    );

    if (rotation == null) return null;

    final InputImageFormat format = Platform.isAndroid
        ? InputImageFormat.nv21
        : InputImageFormat.bgra8888;

    if (!_validateFormat(image, format)) {
      return null;
    }

    final Uint8List bytes = _concatenatePlanes(image.planes);

    final InputImageMetadata metadata = InputImageMetadata(
      size: Size(image.width.toDouble(), image.height.toDouble()),
      rotation: rotation,
      format: format,
      bytesPerRow: image.planes.first.bytesPerRow,
    );

    return InputImage.fromBytes(bytes: bytes, metadata: metadata);
  }

  static InputImageRotation? _getImageRotation(
    CameraDescription camera,
    DeviceOrientation deviceOrientation,
  ) {
    final int sensorOrientation = camera.sensorOrientation;

    if (Platform.isIOS) {
      return InputImageRotationValue.fromRawValue(sensorOrientation);
    }

    final int? rotationCompensation = _orientations[deviceOrientation];
    if (rotationCompensation == null) return null;

    int adjustedRotation;
    if (camera.lensDirection == CameraLensDirection.front) {
      adjustedRotation = (sensorOrientation + rotationCompensation) % 360;
    } else {
      adjustedRotation = (sensorOrientation - rotationCompensation + 360) % 360;
    }

    return InputImageRotationValue.fromRawValue(adjustedRotation);
  }

  static bool _validateFormat(CameraImage image, InputImageFormat expectedFormat) {
    if (Platform.isAndroid) {
      return image.format.group == ImageFormatGroup.nv21;
    } else {
      return image.format.group == ImageFormatGroup.bgra8888;
    }
  }

  static Uint8List _concatenatePlanes(List<Plane> planes) {
    final WriteBuffer allBytes = WriteBuffer();
    for (final Plane plane in planes) {
      allBytes.putUint8List(plane.bytes);
    }
    return allBytes.done().buffer.asUint8List();
  }
}
