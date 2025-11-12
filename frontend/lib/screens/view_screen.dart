import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../services/api_service.dart';
import 'product_detail_screen.dart';

class ViewScreen extends StatefulWidget {
  const ViewScreen({super.key});

  @override
  State<ViewScreen> createState() => _ViewScreenState();
}

class _ViewScreenState extends State<ViewScreen> {
  final MobileScannerController cameraController = MobileScannerController();
  bool isScanning = false;

  @override
  void dispose() {
    cameraController.dispose();
    super.dispose();
  }

  Future<void> _handleBarcode(BarcodeCapture barcodeCapture) async {
    if (isScanning) return;
    
    final List<Barcode> barcodes = barcodeCapture.barcodes;
    if (barcodes.isEmpty) return;

    final String? barcode = barcodes.first.rawValue;
    if (barcode == null || barcode.isEmpty) return;

    setState(() {
      isScanning = true;
    });

    try {
      // Stop camera
      await cameraController.stop();
      
      // Fetch product details
      final product = await ApiService.getProductByBarcode(barcode);
      
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ProductDetailScreen(product: product),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
        // Restart camera on error
        await cameraController.start();
      }
    } finally {
      if (mounted) {
        setState(() {
          isScanning = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan QR Code'),
      ),
      body: Stack(
        children: [
          // Camera view
          MobileScanner(
            controller: cameraController,
            onDetect: _handleBarcode,
          ),
          // Overlay with instructions
          Positioned(
            top: 50,
            left: 0,
            right: 0,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Position the QR code within the frame',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          // Scanning indicator
          if (isScanning)
            const Center(
              child: CircularProgressIndicator(
                color: Color(0xFFD4AF37),
              ),
            ),
        ],
      ),
    );
  }
}


