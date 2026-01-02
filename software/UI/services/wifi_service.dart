/**
 * A majority of this code was written by AI.
 * 
 * Script Name: wifi_service.dart
 * Description: 
 *   Backend service for interfacing with NetworkManager via `nmcli`. 
 *   Handles scanning, authentication, and status reporting for Wi-Fi.
 */

import 'dart:async';
import 'dart:convert';
import 'dart:io';

class WifiNetwork {
  final String ssid;
  final int signal; // 0-100
  final bool secure;
  final String security; // e.g., WPA2, WPA3, --

  WifiNetwork({
    required this.ssid,
    required this.signal,
    required this.secure,
    required this.security,
  });
}

class WifiStatus {
  final bool wifiEnabled;
  final bool connected;
  final String? ssid;
  final String? device;
  final String? error;

  const WifiStatus({
    required this.wifiEnabled,
    required this.connected,
    this.ssid,
    this.device,
    this.error,
  });
}

class WifiService {
  static bool get isLinux => Platform.isLinux;

  static Future<bool> hasNmcli() async {
    if (!isLinux) return false;
    try {
      final which = await Process.run('bash', [
        '-lc',
        'command -v nmcli || true',
      ]);
      final path = (which.stdout as String?)?.trim();
      return path != null && path.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static Future<WifiStatus> getStatus() async {
    if (!await hasNmcli()) {
      return const WifiStatus(
        wifiEnabled: false,
        connected: false,
        error: 'nmcli not found',
      );
    }
    try {
      // 1) Get Wi‑Fi radio status (nmcli general)
      // Prefer: nmcli -t -f WIFI g   -> enabled|disabled
      var wifiEnabled = false;
      var wifiErr = '';
      final resWifi = await _run(['-t', '-f', 'WIFI', 'general', 'status']);
      if (resWifi.exitCode == 0) {
        final val = (resWifi.stdout as String)
            .trim()
            .split('\n')
            .firstWhere((_) => true, orElse: () => '');
        wifiEnabled = val == 'enabled';
      } else {
        // Fallback for older nmcli
        final resRadio = await _run(['radio', 'wifi']);
        if (resRadio.exitCode == 0) {
          wifiEnabled = (resRadio.stdout as String).trim() == 'enabled';
        } else {
          wifiErr = (resWifi.stderr as String).isNotEmpty
              ? (resWifi.stderr as String)
              : (resRadio.stderr as String);
        }
      }

      // 2) Find connected Wi‑Fi device and SSID via device status
      // nmcli -t -f DEVICE,TYPE,STATE,CONNECTION device status
      String? ssid;
      String? dev;
      var connected = false;
      final resDev = await _run([
        '-t',
        '-f',
        'DEVICE,TYPE,STATE,CONNECTION',
        'device',
        'status',
      ]);
      if (resDev.exitCode == 0) {
        final lines = (resDev.stdout as String).trim().split('\n');
        for (final l in lines) {
          if (l.trim().isEmpty) continue;
          final p = l.split(':');
          if (p.length < 4) continue;
          final d = p[0];
          final type = p[1];
          final state = p[2];
          final conn = p[3];
          if (type == 'wifi' && state == 'connected') {
            dev = d;
            ssid = conn.isNotEmpty ? conn : null;
            connected = true;
            break;
          }
        }
      }

      return WifiStatus(
        wifiEnabled: wifiEnabled,
        connected: connected,
        ssid: ssid,
        device: dev,
        error: wifiErr.isEmpty ? null : wifiErr,
      );
    } catch (e) {
      return WifiStatus(wifiEnabled: false, connected: false, error: '$e');
    }
  }

  static Future<bool> setWifiEnabled(bool on) async {
    if (!await hasNmcli()) return false;
    final cmd = on ? 'on' : 'off';
    final res = await _run(['radio', 'wifi', cmd]);
    return res.exitCode == 0;
  }

  static Future<List<WifiNetwork>> scan({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    if (!await hasNmcli()) return [];
    // Use terse output: SSID:SIGNAL:SECURITY
    final res = await _run([
      '-t',
      '-f',
      'SSID,SIGNAL,SECURITY',
      'device',
      'wifi',
      'list',
    ], timeout: timeout);
    if (res.exitCode != 0) {
      return [];
    }
    final lines = const LineSplitter().convert((res.stdout as String));
    final Map<String, WifiNetwork> unique = {};
    for (final l in lines) {
      if (l.trim().isEmpty) continue;
      final parts = l.split(':');
      // nmcli may include additional colons when fields are empty; guard length
      final ssid = parts.isNotEmpty ? parts[0] : '';
      if (ssid.isEmpty) continue; // hide hidden/blank entries
      final signalStr = parts.length > 1 && parts[1].isNotEmpty
          ? parts[1]
          : '0';
      final sec = parts.length > 2 ? parts.sublist(2).join(':') : '--';
      final signal = int.tryParse(signalStr) ?? 0;
      final secure = sec != '--';
      final item = WifiNetwork(
        ssid: ssid,
        signal: signal,
        secure: secure,
        security: sec,
      );
      // Prefer the strongest signal for duplicate SSIDs
      final existing = unique[ssid];
      if (existing == null || item.signal > existing.signal) {
        unique[ssid] = item;
      }
    }
    final list = unique.values.toList()
      ..sort((a, b) => b.signal.compareTo(a.signal));
    return list;
  }

  static Future<WifiStatus> connect(
    String ssid, {
    String? password,
    bool hidden = false,
  }) async {
    if (!await hasNmcli()) {
      return const WifiStatus(
        wifiEnabled: false,
        connected: false,
        error: 'nmcli not found',
      );
    }
    // Build arguments safely; nmcli handles quoting if we pass as separate args
    final args = ['device', 'wifi', 'connect', ssid];
    if ((password ?? '').isNotEmpty) {
      args.addAll(['password', password!]);
    }
    if (hidden) {
      args.addAll(['hidden', 'yes']);
    }
    final res = await _run(args, timeout: const Duration(seconds: 20));
    if (res.exitCode != 0) {
      return WifiStatus(
        wifiEnabled: true,
        connected: false,
        error: (res.stderr as String).trim(),
      );
    }
    // Verify status
    return getStatus();
  }

  static Future<WifiStatus> disconnect() async {
    if (!await hasNmcli()) {
      return const WifiStatus(
        wifiEnabled: false,
        connected: false,
        error: 'nmcli not found',
      );
    }
    // Find active device
    final st = await getStatus();
    final dev = st.device;
    if (dev == null || dev.isEmpty) return st;
    final res = await _run(['device', 'disconnect', dev]);
    if (res.exitCode != 0) {
      return WifiStatus(
        wifiEnabled: st.wifiEnabled,
        connected: st.connected,
        ssid: st.ssid,
        device: st.device,
        error: (res.stderr as String).trim(),
      );
    }
    return WifiStatus(wifiEnabled: st.wifiEnabled, connected: false);
  }

  static Future<ProcessResult> _run(
    List<String> args, {
    Duration? timeout,
  }) async {
    // Execute nmcli with a login shell for PATH correctness
    final full = ['-lc', 'nmcli ${args.map(_shEscape).join(' ')}'];
    try {
      if (timeout != null) {
        final proc = await Process.start('bash', full);
        final out = await proc.stdout.transform(utf8.decoder).join();
        final err = await proc.stderr.transform(utf8.decoder).join();
        final code = await proc.exitCode.timeout(
          timeout,
          onTimeout: () {
            proc.kill(ProcessSignal.sigkill);
            return -1;
          },
        );
        return ProcessResult(proc.pid, code, out, err);
      }
      return await Process.run('bash', full);
    } catch (e) {
      return ProcessResult(0, -1, '', '$e');
    }
  }

  static String _shEscape(String s) {
    // Simple shell-safe escaping by single-quoting, with inner quotes handled
    if (s.isEmpty) return "''";
    return "'${s.replaceAll("'", "'\\''")}'";
  }
}
