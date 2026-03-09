import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'device_detail_page.dart';

void main() {
  FlutterBluePlus.setLogLevel(LogLevel.verbose, color: true);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BLE Scanner',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const ScannerPage(),
    );
  }
}

class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  List<ScanResult> _scanResults = [];
  bool _isScanning = false;
  StreamSubscription<List<ScanResult>>? _scanResultsSub;
  StreamSubscription<bool>? _isScanSub;

  @override
  void initState() {
    super.initState();

    _isScanSub = FlutterBluePlus.isScanning.listen((scanning) {
      if (mounted) setState(() => _isScanning = scanning);
    });

    _scanResultsSub = FlutterBluePlus.onScanResults.listen((results) {
      if (mounted) {
        setState(() {
          _scanResults = results;
          _scanResults.sort((a, b) => b.rssi.compareTo(a.rssi));
        });
      }
    }, onError: (e) {
      debugPrint('Scan error: $e');
    });
  }

  @override
  void dispose() {
    _scanResultsSub?.cancel();
    _isScanSub?.cancel();
    super.dispose();
  }

  Future<void> _requestPermissions() async {
    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
  }

  Future<void> _startScan() async {
    await _requestPermissions();

    try {
      final adapterState = await FlutterBluePlus.adapterState.first;
      if (adapterState != BluetoothAdapterState.on) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please turn on Bluetooth')),
          );
        }
        return;
      }

      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 15),
        androidUsesFineLocation: true,
      );
    } catch (e) {
      debugPrint('Start scan error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Scan failed: $e')),
        );
      }
    }
  }

  Future<void> _stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (e) {
      debugPrint('Stop scan error: $e');
    }
  }

  Widget _buildDeviceTile(ScanResult result) {
    final device = result.device;
    final name = device.platformName.isNotEmpty
        ? device.platformName
        : result.advertisementData.advName.isNotEmpty
            ? result.advertisementData.advName
            : 'Unknown Device';
    final isWhoop = name.toUpperCase().contains('WHOOP');

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      color: isWhoop ? Colors.teal.shade50 : null,
      child: ListTile(
        leading: Icon(
          isWhoop ? Icons.watch : Icons.bluetooth,
          color: isWhoop ? Colors.teal : Colors.blueGrey,
          size: 32,
        ),
        title: Text(
          name,
          style: TextStyle(
            fontWeight: isWhoop ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ID: ${device.remoteId}'),
            Text('RSSI: ${result.rssi} dBm'),
            if (result.advertisementData.serviceUuids.isNotEmpty)
              Text(
                'Services: ${result.advertisementData.serviceUuids.join(', ')}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
        trailing: isWhoop
            ? const Chip(
                label: Text('WHOOP', style: TextStyle(color: Colors.white, fontSize: 11)),
                backgroundColor: Colors.teal,
              )
            : null,
        isThreeLine: true,
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => DeviceDetailPage(device: device),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('BLE Scanner'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          if (_isScanning)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isScanning ? null : _startScan,
                    icon: const Icon(Icons.search),
                    label: const Text('Scan for Devices'),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _isScanning ? _stopScan : null,
                  icon: const Icon(Icons.stop),
                  label: const Text('Stop'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade100,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text(
                  '${_scanResults.length} device(s) found',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const Spacer(),
                if (_isScanning)
                  Text(
                    'Scanning...',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Colors.teal),
                  ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: _scanResults.isEmpty
                ? Center(
                    child: Text(
                      _isScanning
                          ? 'Searching for BLE devices...'
                          : 'Tap "Scan for Devices" to begin',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  )
                : ListView.builder(
                    itemCount: _scanResults.length,
                    itemBuilder: (context, index) {
                      return _buildDeviceTile(_scanResults[index]);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
