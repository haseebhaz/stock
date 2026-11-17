import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Backup scanner using the device camera (with flashlight). Returns the barcode text.
class CameraScanScreen extends StatefulWidget {
  const CameraScanScreen({super.key});
  @override
  State<CameraScanScreen> createState() => _CameraScanScreenState();
}

class _CameraScanScreenState extends State<CameraScanScreen> {
  final _controller = MobileScannerController();
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Camera scan'),
        actions: [
          IconButton(
            tooltip: 'Flashlight',
            icon: const Icon(Icons.flashlight_on),
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: MobileScanner(
        controller: _controller,
        onDetect: (capture) {
          if (_done) return;
          final code = capture.barcodes.map((b) => b.rawValue).whereType<String>().firstOrNull;
          if (code == null || code.isEmpty) return;
          _done = true;
          Navigator.of(context).pop(code);
        },
        errorBuilder: (context, error) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Camera not available: ${error.errorCode.name}.\nAllow camera access in Android settings.'),
          ),
        ),
      ),
    );
  }
}
