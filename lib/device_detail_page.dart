import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class DeviceDetailPage extends StatefulWidget {
  final BluetoothDevice device;

  const DeviceDetailPage({super.key, required this.device});

  @override
  State<DeviceDetailPage> createState() => _DeviceDetailPageState();
}

class _DeviceDetailPageState extends State<DeviceDetailPage> {
  BluetoothConnectionState _connectionState =
      BluetoothConnectionState.disconnected;
  List<BluetoothService> _services = [];
  bool _isConnecting = false;
  bool _isDiscoveringServices = false;
  StreamSubscription<BluetoothConnectionState>? _connectionSub;
  int? _rssi;

  @override
  void initState() {
    super.initState();

    _connectionSub =
        widget.device.connectionState.listen((state) {
      if (mounted) {
        setState(() => _connectionState = state);
        if (state == BluetoothConnectionState.disconnected) {
          setState(() => _services = []);
        }
      }
    });
  }

  @override
  void dispose() {
    _connectionSub?.cancel();
    super.dispose();
  }

  bool get _isConnected =>
      _connectionState == BluetoothConnectionState.connected;

  Future<void> _connect() async {
    setState(() => _isConnecting = true);
    try {
      await widget.device.connect(timeout: const Duration(seconds: 15));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Connected!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Connect failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isConnecting = false);
    }
  }

  Future<void> _disconnect() async {
    try {
      await widget.device.disconnect();
    } catch (e) {
      debugPrint('Disconnect error: $e');
    }
  }

  Future<void> _discoverServices() async {
    setState(() => _isDiscoveringServices = true);
    try {
      final services = await widget.device.discoverServices();
      if (mounted) setState(() => _services = services);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Service discovery failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isDiscoveringServices = false);
    }
  }

  Future<void> _readRssi() async {
    try {
      final rssi = await widget.device.readRssi();
      if (mounted) setState(() => _rssi = rssi);
    } catch (e) {
      debugPrint('Read RSSI error: $e');
    }
  }

  Future<void> _readCharacteristic(BluetoothCharacteristic c) async {
    try {
      final value = await c.read();
      if (mounted) {
        _showDataDialog('Read Value', c.uuid.toString(), value);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Read failed: $e')),
        );
      }
    }
  }

  Future<void> _writeCharacteristic(BluetoothCharacteristic c) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Write Value'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Enter text or hex (e.g. 0x01FF)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Write'),
          ),
        ],
      ),
    );

    if (result == null || result.isEmpty) return;

    try {
      List<int> bytes;
      if (result.startsWith('0x') || result.startsWith('0X')) {
        final hex = result.substring(2);
        bytes = List.generate(
          hex.length ~/ 2,
          (i) => int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16),
        );
      } else {
        bytes = utf8.encode(result);
      }

      await c.write(bytes);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Write successful')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Write failed: $e')),
        );
      }
    }
  }

  Future<void> _toggleNotify(BluetoothCharacteristic c) async {
    try {
      await c.setNotifyValue(!c.isNotifying);
      if (c.isNotifying) {
        c.onValueReceived.listen((value) {
          debugPrint(
            'Notification from ${c.uuid}: ${_formatBytes(value)}',
          );
        });
      }
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Notify toggle failed: $e')),
        );
      }
    }
  }

  String _formatBytes(List<int> bytes) {
    if (bytes.isEmpty) return '(empty)';
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
    final ascii = String.fromCharCodes(
      bytes.where((b) => b >= 32 && b <= 126),
    );
    return 'HEX: $hex${ascii.isNotEmpty ? '\nASCII: $ascii' : ''}';
  }

  void _showDataDialog(String title, String uuid, List<int> value) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('UUID: $uuid', style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 8),
            Text('Length: ${value.length} bytes'),
            const SizedBox(height: 8),
            SelectableText(_formatBytes(value)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Widget _buildServiceTile(BluetoothService service) {
    return ExpansionTile(
      title: Text(
        'Service: ${service.uuid}',
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
      ),
      subtitle: Text('${service.characteristics.length} characteristic(s)'),
      children: service.characteristics.map(_buildCharacteristicTile).toList(),
    );
  }

  Widget _buildCharacteristicTile(BluetoothCharacteristic c) {
    final props = c.properties;
    final propLabels = <String>[];
    if (props.read) propLabels.add('READ');
    if (props.write) propLabels.add('WRITE');
    if (props.writeWithoutResponse) propLabels.add('WRITE_NR');
    if (props.notify) propLabels.add('NOTIFY');
    if (props.indicate) propLabels.add('INDICATE');

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Char: ${c.uuid}',
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              children: propLabels
                  .map((l) => Chip(
                        label: Text(l, style: const TextStyle(fontSize: 10)),
                        padding: EdgeInsets.zero,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ))
                  .toList(),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (props.read)
                  _actionButton(Icons.download, 'Read', () => _readCharacteristic(c)),
                if (props.write || props.writeWithoutResponse)
                  _actionButton(Icons.upload, 'Write', () => _writeCharacteristic(c)),
                if (props.notify || props.indicate)
                  _actionButton(
                    c.isNotifying ? Icons.notifications_active : Icons.notifications_off,
                    c.isNotifying ? 'Unsub' : 'Subscribe',
                    () => _toggleNotify(c),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionButton(IconData icon, String label, VoidCallback onPressed) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 16),
        label: Text(label, style: const TextStyle(fontSize: 12)),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          minimumSize: Size.zero,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.device.platformName.isNotEmpty
              ? widget.device.platformName
              : widget.device.remoteId.toString(),
        ),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Column(
        children: [
          // Connection status card
          Card(
            margin: const EdgeInsets.all(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(
                        _isConnected
                            ? Icons.bluetooth_connected
                            : Icons.bluetooth_disabled,
                        color: _isConnected ? Colors.teal : Colors.grey,
                        size: 28,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _isConnected ? 'Connected' : 'Disconnected',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: _isConnected ? Colors.teal : Colors.grey,
                              ),
                            ),
                            Text(
                              'ID: ${widget.device.remoteId}',
                              style: const TextStyle(fontSize: 12),
                            ),
                            if (_rssi != null)
                              Text('RSSI: $_rssi dBm',
                                  style: const TextStyle(fontSize: 12)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _isConnecting
                              ? null
                              : (_isConnected ? _disconnect : _connect),
                          child: _isConnecting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                )
                              : Text(_isConnected ? 'Disconnect' : 'Connect'),
                        ),
                      ),
                      if (_isConnected) ...[
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed:
                              _isDiscoveringServices ? null : _discoverServices,
                          child: _isDiscoveringServices
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                )
                              : const Text('Discover Services'),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: _readRssi,
                          icon: const Icon(Icons.signal_cellular_alt),
                          tooltip: 'Read RSSI',
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Services list
          if (_services.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${_services.length} service(s) discovered',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            ),
          Expanded(
            child: _services.isEmpty
                ? Center(
                    child: Text(
                      _isConnected
                          ? 'Tap "Discover Services" to explore'
                          : 'Connect to the device first',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  )
                : ListView.builder(
                    itemCount: _services.length,
                    itemBuilder: (context, index) {
                      return _buildServiceTile(_services[index]);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
