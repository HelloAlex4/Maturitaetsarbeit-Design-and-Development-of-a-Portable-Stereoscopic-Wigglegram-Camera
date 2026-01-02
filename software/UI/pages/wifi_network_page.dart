/**
 * A majority of this code was written by AI.
 * 
 * Script Name: wifi_network_page.dart
 * Description: 
 *   Provides a UI for scanning, connecting to, and disconnecting from 
 *   Wi-Fi networks using `nmcli` on the Raspberry Pi host.
 */

import 'package:flutter/material.dart';

import 'package:camera/services/wifi_service.dart';
import 'package:camera/widgets/battery_indicator.dart';

class WifiNetworkPage extends StatefulWidget {
  const WifiNetworkPage({super.key});

  @override
  State<WifiNetworkPage> createState() => _WifiNetworkPageState();
}

class _WifiNetworkPageState extends State<WifiNetworkPage> {
  bool _loading = true;
  bool _wifiEnabled = true;
  String? _error;
  List<WifiNetwork> _networks = const [];
  WifiStatus? _status;

  final _passwordControllers = <String, TextEditingController>{};

  @override
  void initState() {
    super.initState();
    _refreshAll();
  }

  @override
  void dispose() {
    for (final c in _passwordControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _refreshAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final has = await WifiService.hasNmcli();
    if (!has) {
      setState(() {
        _loading = false;
        _error =
            'nmcli not found. Install NetworkManager (nmcli) on Raspberry Pi OS.';
      });
      return;
    }
    final status = await WifiService.getStatus();
    final nets = await WifiService.scan();
    setState(() {
      _status = status;
      _wifiEnabled = status.wifiEnabled;
      _networks = nets;
      _error = status.error;
      _loading = false;
    });
  }

  Future<void> _toggleWifi(bool on) async {
    setState(() => _loading = true);
    await WifiService.setWifiEnabled(on);
    await _refreshAll();
  }

  Future<void> _connect(WifiNetwork n) async {
    // Open networks: connect immediately. Secure networks: prompt for password if not stored.
    if (!n.secure) {
      await _connectWithPassword(n, null);
      return;
    }
    final existing = _passwordControllers[n.ssid]?.text;
    if (existing != null && existing.isNotEmpty) {
      await _connectWithPassword(n, existing);
      return;
    }
    await _promptPasswordAndConnect(n);
  }

  Future<void> _connectWithPassword(WifiNetwork n, String? password) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final st = await WifiService.connect(n.ssid, password: password);
    setState(() {
      _status = st;
      _error = st.error;
      _loading = false;
    });
    if (st.connected && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Connected to ${st.ssid ?? n.ssid}')),
      );
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _promptPasswordAndConnect(WifiNetwork n) async {
    final controller = _passwordControllers.putIfAbsent(
      n.ssid,
      () => TextEditingController(),
    );
    String? entered;
    await showDialog<void>(
      context: context,
      builder: (context) {
        bool obscure = true;
        return StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: Text('Connect to ${n.ssid}'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  obscureText: obscure,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscure ? Icons.visibility : Icons.visibility_off,
                      ),
                      onPressed: () => setState(() => obscure = !obscure),
                    ),
                  ),
                  onSubmitted: (v) {
                    entered = v;
                    Navigator.of(context).pop();
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  entered = controller.text;
                  Navigator.of(context).pop();
                },
                child: const Text('Connect'),
              ),
            ],
          ),
        );
      },
    );
    if ((entered ?? controller.text).isNotEmpty) {
      await _connectWithPassword(n, entered ?? controller.text);
    }
  }

  Future<void> _disconnect() async {
    setState(() => _loading = true);
    final st = await WifiService.disconnect();
    setState(() {
      _status = st;
      _error = st.error;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final busy = _loading;
    final connectedTo = _status?.connected == true ? _status?.ssid : null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wi‑Fi Networks'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Center(
              child: BatteryIndicator(
                textStyle: const TextStyle(fontSize: 14),
              ),
            ),
          ),
          IconButton(
            onPressed: busy ? null : _refreshAll,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          SwitchListTile(
            title: const Text('Enable Wi‑Fi'),
            value: _wifiEnabled,
            onChanged: busy ? null : (v) => _toggleWifi(v),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          if (!_wifiEnabled)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Wi‑Fi is disabled.'),
            ),
          if (_wifiEnabled)
            Expanded(
              child: busy
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.separated(
                      itemCount: _networks.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final n = _networks[i];
                        final connected = connectedTo == n.ssid;
                        // No password field until user taps Connect
                        return ListTile(
                          leading: Icon(
                            Icons.wifi,
                            color: connected ? Colors.green : null,
                          ),
                          title: Text(n.ssid),
                          subtitle: Text('${n.security}  •  ${n.signal}%'),
                          trailing: connected
                              ? TextButton(
                                  onPressed: _disconnect,
                                  child: const Text('Disconnect'),
                                )
                              : TextButton(
                                  onPressed: () => _connect(n),
                                  child: const Text('Connect'),
                                ),
                          onTap: () {},
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                        );
                      },
                    ),
            ),
        ],
      ),
      // Password field is shown on-demand via dialog
      bottomNavigationBar: null,
    );
  }
}
