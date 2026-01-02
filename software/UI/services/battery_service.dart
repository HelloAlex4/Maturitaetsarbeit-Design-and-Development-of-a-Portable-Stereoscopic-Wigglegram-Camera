/**
 * A majority of this code was written by AI.
 * 
 * Script Name: battery_service.dart
 * Description: 
 *   Service for monitoring device battery levels by executing the 
 *   `readVoltage` C binary on the Raspberry Pi.
 */

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

class BatteryService {
  BatteryService._();

  static String? _cachedBinaryPath;

  static Future<double?> readBatteryPercent() async {
    try {
      final binary = await _locateReadVoltageBinary();
      if (binary == null) return null;

      final result = await Process.run(
        binary,
        const <String>[],
        workingDirectory: p.dirname(p.dirname(binary)),
      );
      if (result.exitCode != 0) return null;

      final stdoutObj = result.stdout;
      final String rawOut;
      if (stdoutObj is List<int>) {
        rawOut = utf8.decode(stdoutObj);
      } else {
        rawOut = stdoutObj?.toString() ?? '';
      }
      final trimmed = rawOut.trim();
      if (trimmed.isEmpty) return null;

      final percent = double.tryParse(trimmed);
      if (percent == null) return null;

      return percent.clamp(0.0, 100.0);
    } catch (_) {
      return null;
    }
  }

  static Future<String?> _locateReadVoltageBinary() async {
    if (_cachedBinaryPath != null) {
      final cachedFile = File(_cachedBinaryPath!);
      if (await cachedFile.exists()) {
        return _cachedBinaryPath;
      }
      _cachedBinaryPath = null;
    }

    final found = await _findInParents('scripts/readVoltage');
    if (found != null) {
      _cachedBinaryPath = found;
    }
    return found;
  }

  static Future<String?> _findInParents(
    String relativePath, {
    int maxLevels = 6,
  }) async {
    final direct = File(relativePath);
    if (await direct.exists()) return direct.path;

    final cwd = Directory.current.path;
    final fromCwd = File(p.join(cwd, relativePath));
    if (await fromCwd.exists()) return fromCwd.path;

    final execDir = Directory(p.dirname(Platform.resolvedExecutable));
    final fromExec = File(p.join(execDir.path, relativePath));
    if (await fromExec.exists()) return fromExec.path;

    final fromExecParent = File(p.join(execDir.parent.path, relativePath));
    if (await fromExecParent.exists()) return fromExecParent.path;

    Directory probe = Directory(cwd);
    for (int i = 0; i < maxLevels; i++) {
      final candidate = File(p.join(probe.path, relativePath));
      if (await candidate.exists()) return candidate.path;
      final next = probe.parent;
      if (next.path == probe.path) break;
      probe = next;
    }

    return null;
  }
}
