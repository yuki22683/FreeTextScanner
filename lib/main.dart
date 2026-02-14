import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/text_scanner_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  runApp(const FreeTextScannerApp());
}

class FreeTextScannerApp extends StatelessWidget {
  const FreeTextScannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Free Text Scanner',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const TextScannerScreen(),
    );
  }
}
