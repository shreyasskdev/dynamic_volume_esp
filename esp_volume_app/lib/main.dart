import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_classic_serial/flutter_bluetooth_classic.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const EspVolumeApp());
}

class EspVolumeApp extends StatelessWidget {
  const EspVolumeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ESP32 Auto-Volume',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF121212),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFBB86FC),
          secondary: Color(0xFF03DAC6),
        ),
      ),
      home: const VolumeDashboard(),
    );
  }
}

class VolumeDashboard extends StatefulWidget {
  const VolumeDashboard({super.key});

  @override
  State<VolumeDashboard> createState() => _VolumeDashboardState();
}

class _VolumeDashboardState extends State<VolumeDashboard> {
  final FlutterBluetoothClassic _bluetooth = FlutterBluetoothClassic();
  List<BluetoothDevice> _pairedDevices = [];
  bool _isConnected = false;
  String _statusText = "Not Connected";
  String _buffer = "";

  // Live Data from ESP32
  double _noise = 0;
  int _vol = 35;
  double _quiet = 2000;
  double _loud = 4500;
  bool _autoRange = true;

  // Text Controllers for Settings
  final TextEditingController _quietCtrl = TextEditingController(text: "2000");
  final TextEditingController _loudCtrl = TextEditingController(text: "4500");
  final TextEditingController _minvCtrl = TextEditingController(text: "35");
  final TextEditingController _maxvCtrl = TextEditingController(text: "127");
  bool _firstSync = true;

  @override
  void initState() {
    super.initState();
    _initBluetooth();
  }

  Future<void> _initBluetooth() async {
    // Request Android 12+ Bluetooth permissions
    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();

    _pairedDevices = await _bluetooth.getPairedDevices();
    setState(() {});

    // Listen to incoming serial stream from ESP32
    _bluetooth.onDataReceived.listen((BluetoothData data) {
      _buffer += data.asString();
      while (_buffer.contains('\n')) {
        int index = _buffer.indexOf('\n');
        String line = _buffer.substring(0, index).trim();
        _buffer = _buffer.substring(index + 1);
        if (line.startsWith('{') && line.endsWith('}')) {
          _parseJson(line);
        }
      }
    });

    _bluetooth.onConnectionChanged.listen((state) {
      setState(() {
        _isConnected = state.isConnected;
        _statusText = _isConnected ? "Connected to ESP32" : "Disconnected";
      });
    });

    // Auto-connect if "ESP32 Speaker" is already paired
    for (var d in _pairedDevices) {
      if (d.name.contains("ESP32")) {
        _connectToDevice(d);
        break;
      }
    }
  }

  void _parseJson(String jsonStr) {
    try {
      final d = jsonDecode(jsonStr);
      setState(() {
        _noise = (d['noise'] ?? 0).toDouble();
        _vol = (d['vol'] ?? 0).toInt();
        _quiet = (d['quiet'] ?? 2000).toDouble();
        _loud = (d['loud'] ?? 4500).toDouble();
        _autoRange = (d['auto'] ?? 1) == 1;

        if (_autoRange || _firstSync) {
          _quietCtrl.text = _quiet.round().toString();
          _loudCtrl.text = _loud.round().toString();
        }
        if (_firstSync) {
          _minvCtrl.text = (d['minv'] ?? 35).toString();
          _maxvCtrl.text = (d['maxv'] ?? 127).toString();
          _firstSync = false;
        }
      });
    } catch (_) {}
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    setState(() => _statusText = "Connecting to ${device.name}...");
    bool ok = await _bluetooth.connect(device.address);
    setState(() {
      _isConnected = ok;
      _statusText = ok ? "Connected to ${device.name}" : "Connection Failed";
    });
  }

  Future<void> _sendSettings() async {
    if (!_isConnected) return;
    int a = _autoRange ? 1 : 0;
    String cmd =
        "SET:$a,${_quietCtrl.text},${_loudCtrl.text},${_minvCtrl.text},${_maxvCtrl.text}\n";
    await _bluetooth.sendString(cmd);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Settings sent to ESP32!"),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    double span = (_loud - _quiet).clamp(1.0, 100000.0);
    double noisePct = ((_noise - _quiet) / span).clamp(0.0, 1.0);
    double volPct = (_vol / 127.0).clamp(0.0, 1.0);

    return Scaffold(
      appBar: AppBar(
        title: const Text("ESP32 Auto-Volume"),
        backgroundColor: const Color(0xFF1E1E1E),
        actions: [
          IconButton(
            icon: Icon(_isConnected
                ? Icons.bluetooth_connected
                : Icons.bluetooth_disabled),
            color:
            _isConnected ? const Color(0xFF03DAC6) : Colors.redAccent,
            onPressed: _showDevicePicker,
          )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(_statusText,
                style: TextStyle(
                    color: _isConnected
                        ? const Color(0xFF03DAC6)
                        : Colors.orangeAccent)),
            const SizedBox(height: 12),

            // --- Mic Noise Card ---
            _buildMeterCard(
              title: "Mic Noise Input (RMS)",
              valueText: _noise.round().toString(),
              progress: noisePct,
              barColor: const Color(0xFF03DAC6),
              subtitle:
              "Range: ${_quiet.round()} (Quiet) – ${_loud.round()} (Loud Peak)",
            ),
            const SizedBox(height: 16),

            // --- Speaker Volume Card ---
            _buildMeterCard(
              title: "Adjusted Speaker Volume",
              valueText: "$_vol / 127",
              progress: volPct,
              barColor: const Color(0xFFBB86FC),
              subtitle: "${(volPct * 100).round()}%",
            ),
            const SizedBox(height: 16),

            // --- Settings Card ---
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  const Text("Settings",
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF03DAC6))),
                  SwitchListTile(
                    title: const Text("Auto-Adjust Noise Range"),
                    value: _autoRange,
                    activeColor: const Color(0xFF03DAC6),
                    onChanged: (val) {
                      setState(() => _autoRange = val);
                      _sendSettings();
                    },
                  ),
                  _buildNumberRow("Quiet Level (Min Noise):", _quietCtrl),
                  _buildNumberRow("Loud Level (Max Noise):", _loudCtrl),
                  _buildNumberRow("Min Volume (0-127):", _minvCtrl),
                  _buildNumberRow("Max Volume (0-127):", _maxvCtrl),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFBB86FC),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: _sendSettings,
                      child: const Text("Apply Settings",
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMeterCard({
    required String title,
    required String valueText,
    required double progress,
    required Color barColor,
    required String subtitle,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(title, style: const TextStyle(fontSize: 15)),
          const SizedBox(height: 8),
          Text(valueText,
              style:
              const TextStyle(fontSize: 34, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 20,
              backgroundColor: const Color(0xFF333333),
              valueColor: AlwaysStoppedAnimation<Color>(barColor),
            ),
          ),
          const SizedBox(height: 8),
          Text(subtitle,
              style: const TextStyle(color: Colors.grey, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildNumberRow(String label, TextEditingController controller) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          SizedBox(
            width: 100,
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              decoration: const InputDecoration(
                isDense: true,
                filled: true,
                fillColor: Color(0xFF2C2C2C),
                border: OutlineInputBorder(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showDevicePicker() async {
    _pairedDevices = await _bluetooth.getPairedDevices();
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => ListView(
        children: _pairedDevices
            .map((d) => ListTile(
          leading: const Icon(Icons.speaker),
          title: Text(d.name),
          subtitle: Text(d.address),
          onTap: () {
            Navigator.pop(ctx);
            _connectToDevice(d);
          },
        ))
            .toList(),
      ),
    );
  }
}