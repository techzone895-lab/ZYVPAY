import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../core/protocol.dart';
import 'amount_screen.dart';
import 'send_screen.dart';

/// Scans a UPI QR. Works offline — reading a QR needs only the camera.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final _controller = MobileScannerController();
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture cap) {
    if (_handled) return;
    for (final b in cap.barcodes) {
      final raw = b.rawValue;
      if (raw == null) continue;
      final payee = Payee.fromQr(raw);
      if (payee != null) {
        _handled = true;
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AmountScreen(payee: payee)));
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('QR scan karein'),
        actions: [
          IconButton(onPressed: () => _controller.toggleTorch(), icon: const Icon(Icons.flashlight_on_outlined)),
        ],
      ),
      body: Stack(
        alignment: Alignment.center,
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect, errorBuilder: (ctx, err) => _CameraError(err: err)),
          Container(
            width: 240,
            height: 240,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white, width: 3),
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          Positioned(
            bottom: 28,
            child: TextButton.icon(
              style: TextButton.styleFrom(backgroundColor: Colors.black54, foregroundColor: Colors.white),
              onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const SendScreen())),
              icon: const Icon(Icons.keyboard),
              label: const Text('UPI ID haath se daalein'),
            ),
          ),
        ],
      ),
    );
  }
}

class _CameraError extends StatelessWidget {
  const _CameraError({required this.err});
  final MobileScannerException err;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.no_photography_outlined, color: Colors.white, size: 40),
          const SizedBox(height: 12),
          const Text('Camera nahi khul paaya', style: TextStyle(color: Colors.white)),
          const SizedBox(height: 4),
          Text('Settings mein camera permission dein.', style: TextStyle(color: Colors.white.withValues(alpha: 0.7))),
        ]),
      ),
    );
  }
}
