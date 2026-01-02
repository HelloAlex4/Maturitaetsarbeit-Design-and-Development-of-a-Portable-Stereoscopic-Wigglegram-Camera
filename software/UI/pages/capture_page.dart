/**
 * A majority of this code was written by AI.
 * 
 * Script Name: capture_page.dart
 * Description: 
 *   The primary camera interface. Manages live preview, captures frames,
 *   coordinates with background scripts (LED, fan, USB streaming), and 
 *   handles hardware button integration.
 */

import 'dart:io';
import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../models/camera_enums.dart';
import '../widgets/battery_indicator.dart';
import '../widgets/live_preview.dart';
import '../widgets/settings_overlay.dart';
import '../widgets/shutter_button.dart';
import 'library_page.dart';

class CapturePage extends StatefulWidget {
  const CapturePage({super.key});

  @override
  State<CapturePage> createState() => _CapturePageState();
}

class _CapturePageState extends State<CapturePage> {
  bool _settingsOpen = false;
  FlashSetting _flash = FlashSetting.off;

  bool _ledOpen = false;
  bool _exposureOpen = false;
  double _exposureValue = 5.0; // Default middle value 1-10
  static bool _livePreviewStarted = false;
  static bool _livePreviewStartInFlight = false;
  int _fanLevel = -1; // -1 = unset/off, 0..2 = low/med/high
  bool _captureInProgress = false;
  bool _liveLoopEnabled = false;
  bool _liveTickInFlight = false;
  Timer? _liveTimer;
  Process? _buttonListenerProcess;
  bool _externalButtonEnabled = true;
  String? _projectRoot;

  @override
  void initState() {
    super.initState();
    _locateProjectRoot().then((p) {
      if (mounted) setState(() => _projectRoot = p);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_ensureInitialFanLevel());
      unawaited(_ensureInitialFanLevel());
      unawaited(_ensureLivePreviewStarted());
      unawaited(_startButtonListener());
    });
  }

  @override
  void dispose() {
    _liveTimer?.cancel();
    _buttonListenerProcess?.kill();
    super.dispose();
  }

  static const String _pythonExec = 'python3';
  // static const String _ledScriptPath = 'scripts/ledControl.py';
  static const String _captureBinPath = 'scripts/capture';
  static const String _livePreviewBinPath = 'scripts/livePreview';
  static const String _captureLockPath = 'images/live/capture.lock';

  Future<String?> _findInParents(
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

  Future<String?> _locateLedScript() async {
    return _findInParents('scripts/ledControl.py');
  }

  Future<String?> _locateFanScript() async {
    return _findInParents('scripts/fan_control.py');
  }

  Future<String?> _locateProjectRoot() async {
    final pubspec = await _findInParents('pubspec.yaml');
    if (pubspec != null) return p.dirname(pubspec);

    final streamUsb = await _findInParents('scripts/streamUSB.py');
    if (streamUsb != null) return p.dirname(p.dirname(streamUsb));

    return null;
  }

  Future<String?> _locateStreamUsbScript() async {
    return _findInParents('scripts/streamUSB.py');
  }

  Future<String?> _locateButtonListenerBinary() async {
    return _findInParents('scripts/button');
  }

  Future<void> _startButtonListener() async {
    try {
      final binaryPath = await _locateButtonListenerBinary();
      if (binaryPath == null) {
        debugPrint('Button binary not found');
        return;
      }

      final workDir = p.dirname(p.dirname(binaryPath));
      // Run the compiled C binary directly
      _buttonListenerProcess = await Process.start(
        binaryPath,
        [],
        workingDirectory: workDir,
      );

      // Listen to stdout
      _buttonListenerProcess!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        debugPrint('ButtonListener stdout: $line');
        if (line.trim() == 'BUTTON_PRESSED') {
          if (mounted && _externalButtonEnabled) {
            // Trigger the same action as the on-screen shutter button
            _onCapturePressed();
          }
        }
      });

      // Listen to stderr for debugging
      _buttonListenerProcess!.stderr
          .transform(utf8.decoder)
          .listen((data) {
        debugPrint('ButtonListener stderr: $data');
        if (mounted && data.contains('Error:')) {
           ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('GPIO Error: $data'),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 5),
              ),
            );
        }
      });

    } catch (e) {
      debugPrint('Failed to start button listener: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start GPIO listener: $e')),
        );
      }
    }
  }

  // _ensurePigpiodRunning removed as we are using libgpiod C binary

  Future<void> _runLed(String effect, {bool showToast = true}) async {
    try {
      final scriptPath = await _locateLedScript();
      if (scriptPath == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('LED script not found: scripts/ledControl.py'),
          ),
        );
        return;
      }

      final workDir = p.dirname(p.dirname(scriptPath));
      final eff = effect.trim().toLowerCase();
      if (eff == 'clear' || eff == 'stop') {
        final result = await Process.run(_pythonExec, [
          scriptPath,
          'clear',
        ], workingDirectory: workDir);
        if (!mounted) return;
        if (result.exitCode != 0 && showToast) {
          final stderrStr = (result.stderr as Object?).toString().trim();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'LED clear error (${result.exitCode}): ' + stderrStr,
              ),
            ),
          );
        }
      } else {
        // Start effect in background and return immediately.
        await Process.start(_pythonExec, [
          scriptPath,
          effect,
        ], workingDirectory: workDir);
        if (showToast && mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('LED: ${effect.trim()}')));
        }
      }
    } on ProcessException catch (e) {
      if (!mounted) return;
      if (showToast) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to run LED script: ${e.message}')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      if (showToast) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unknown error while running LED script'),
          ),
        );
      }
    }
  }

  Future<void> _runStreamUsbScript({
    List<String> extraArgs = const [],
    bool silent = false,
  }) async {
    final projectRoot = await _locateProjectRoot();
    if (projectRoot == null) {
      if (!mounted || silent) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Project root not found (pubspec.yaml missing)'),
        ),
      );
      return;
    }

    final lockFile = File(p.join(projectRoot, _captureLockPath));

    final scriptPath = p.join(projectRoot, 'scripts', 'streamUSB.py');
    final scriptFile = File(scriptPath);
    if (!await scriptFile.exists()) {
      if (!mounted || silent) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('streamUSB.py not found at $scriptPath')),
      );
      return;
    }

    // Run using a relative path from the project root so images/ writes work
    final workDir = projectRoot;
    ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? runningSnack;
    final stdoutBuf = StringBuffer();
    final stderrBuf = StringBuffer();

    try {
      await lockFile.parent.create(recursive: true);
      await lockFile.writeAsString('1');

      if (mounted && !silent) {
        runningSnack = ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Running USB capture...'),
            duration: Duration(days: 1),
          ),
        );
      }

      final proc = await Process.start(_pythonExec, [
        'scripts/streamUSB.py',
        ...extraArgs,
      ], workingDirectory: workDir);
      proc.stdout
          .transform(utf8.decoder)
          .listen((chunk) => stdoutBuf.write(chunk));
      proc.stderr
          .transform(utf8.decoder)
          .listen((chunk) => stderrBuf.write(chunk));

      final code = await proc.exitCode;
      if (!mounted) return;

      runningSnack?.close();
      final err = stderrBuf.toString().trim();
      final out = stdoutBuf.toString().trim();
      final combined = err.isNotEmpty ? err : out;
      final brief = combined.length > 240
          ? combined.substring(combined.length - 240)
          : combined;
      final status = code == 0
          ? 'USB capture finished'
          : 'USB capture failed ($code)';
      final detail = brief.isNotEmpty ? ': $brief' : '';
      if (!silent && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$status$detail')));
      }
    } on ProcessException catch (e) {
      runningSnack?.close();
      if (!mounted || silent) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to start streamUSB.py: ${e.message}')),
      );
    } catch (_) {
      runningSnack?.close();
      if (!mounted || silent) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unknown error while running streamUSB')),
      );
    } finally {
      try {
        if (await lockFile.exists()) {
          await lockFile.delete();
        }
      } catch (_) {}
    }
  }

  Future<void> _ensureInitialFanLevel() async {
    if (_fanLevel >= 0) return;
    final ok = await _setFanLevel(1, showToast: false);
    if (ok && mounted) {
      setState(() => _fanLevel = 1);
    }
  }

  Future<bool> _setFanLevel(int level, {bool showToast = true}) async {
    try {
      final scriptPath = await _locateFanScript();
      if (scriptPath == null) {
        if (!mounted) return false;
        if (showToast) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Fan script not found: scripts/fan_control.py'),
            ),
          );
        }
        return false;
      }

      final workDir = p.dirname(p.dirname(scriptPath));
      final levelClamped = level < 0 ? -1 : (level > 2 ? 2 : level);
      final args = levelClamped < 0
          ? [scriptPath, 'off']
          : [scriptPath, 'level', levelClamped.toString()];
      final result = await Process.run(
        _pythonExec,
        args,
        workingDirectory: workDir,
      );
      if (!mounted) return result.exitCode == 0;
      if (result.exitCode == 0) {
        if (showToast) {
          final lbl = levelClamped < 0
              ? 'Off'
              : (levelClamped == 0
                    ? 'Low'
                    : (levelClamped == 1 ? 'Medium' : 'High'));
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Fan: $lbl')));
        }
        return true;
      } else {
        final stderrStr = (result.stderr as Object?).toString().trim();
        if (showToast) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Fan toggle error: $stderrStr')),
          );
        }
        return false;
      }
    } on ProcessException catch (e) {
      if (!mounted) return false;
      if (showToast) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to run fan script: ${e.message}')),
        );
      }
      return false;
    } catch (_) {
      if (!mounted) return false;
      if (showToast) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unknown error while setting fan')),
        );
      }
      return false;
    }
  }

  Future<String?> _locateCaptureBin() async {
    return _findInParents(_captureBinPath);
  }

  Future<String?> _locateLivePreviewBin() async {
    final projectRoot = await _locateProjectRoot();
    if (projectRoot != null) {
      final candidate = File(p.join(projectRoot, _livePreviewBinPath));
      if (await candidate.exists()) return candidate.path;
    }
    return _findInParents(_livePreviewBinPath);
  }

  Future<void> _ensureLivePreviewStarted() async {
    if (_livePreviewStarted || _livePreviewStartInFlight) return;
    _livePreviewStartInFlight = true;
    try {
      final livePath = await _locateLivePreviewBin();
      if (livePath == null) return;
      final workDir = p.dirname(livePath);
      await Process.start(
        livePath,
        const [],
        workingDirectory: workDir,
        runInShell: true,
        mode: ProcessStartMode.detached,
      );
      _livePreviewStarted = true;
    } catch (_) {
      // Best effort; ignore failures so app UI still loads.
    } finally {
      _livePreviewStartInFlight = false;
    }
  }

  Future<void> _flashOnIfEnabled() async {
    if (_flash == FlashSetting.on) {
      await _runLed('white', showToast: false);
    }
  }

  Future<void> _flashOff() async {
    await _runLed('clear', showToast: false);
  }

  Future<void> _confirmExposure() async {
    setState(() => _exposureOpen = false);
    
    // 1. Disable live preview in DB
    await _setLiveFlagInDb(false);

    // 2. Call streamUSB.py with exposure argument
    try {
      await _runStreamUsbScript(
        extraArgs: ['--exposure', _exposureValue.round().toString()],
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to set exposure: $e')),
        );
      }
    }

    // 3. Re-enable live preview in DB
    if (_liveLoopEnabled) {
      await _setLiveFlagInDb(true);
    }
  }

  Future<void> _setLiveFlagInDb(bool live) async {
    try {
      final projectRoot = await _locateProjectRoot();
      if (projectRoot == null) return;
      final dbPath = p.join(projectRoot, 'scripts', 'camera.db');
      final script = '''
import sqlite3, sys
db, live_val = sys.argv[1], int(sys.argv[2])
conn = sqlite3.connect(db)
cur = conn.cursor()
cur.execute("CREATE TABLE IF NOT EXISTS capture (id INTEGER PRIMARY KEY, live BOOLEAN)")
cur.execute("UPDATE capture SET live = ? WHERE id = 1", (live_val,))
if cur.rowcount == 0:
    cur.execute("INSERT INTO capture (id, live) VALUES (1, ?)", (live_val,))
conn.commit()
conn.close()
''';
      await Process.run(_pythonExec, [
        '-c',
        script,
        dbPath,
        live ? '1' : '0',
      ], workingDirectory: projectRoot);
    } catch (_) {
      // Best-effort only; failures are non-fatal for UI flow.
    }
  }

  Future<void> _runCaptureSeries({bool watchForOk = false}) async {
    Process? proc;
    bool turnedOff = false;
    try {
      final capturePath = await _locateCaptureBin();
      if (capturePath == null) {
        if (_flash == FlashSetting.on && !turnedOff) {
          await _flashOff();
          turnedOff = true;
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Capture binary not found: scripts/capture'),
          ),
        );
        return;
      }

      // Prefer running from project root for consistent relative paths
      final workDir = p.dirname(p.dirname(capturePath));
      proc = await Process.start(capturePath, [], workingDirectory: workDir);

      // Watch stdout for success cue to turn off flash quickly
      if (watchForOk) {
        proc.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen((line) {
              final l = line.toLowerCase();
              if (!turnedOff &&
                  (l.contains('captured image') || l.contains('ok'))) {
                turnedOff = true;
                _flashOff();
              }
            });
      }

      // Also drain stderr to avoid blocking
      proc.stderr.drain<void>();

      final code = await proc.exitCode;
      if (watchForOk && !turnedOff) {
        // Safety: ensure flash is off when process exits
        await _flashOff();
        turnedOff = true;
      }
      if (!mounted) return;
      if (code == 0) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Captured series OK')));
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Capture failed ($code)')));
      }
    } on ProcessException catch (e) {
      if (watchForOk && !turnedOff) {
        await _flashOff();
        turnedOff = true;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to start capture: ${e.message}')),
      );
    } catch (e) {
      if (watchForOk && !turnedOff) {
        await _flashOff();
        turnedOff = true;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unknown error during capture')),
      );
    }
  }

  Future<void> _onCapturePressed() async {
    if (!mounted) return;
    if (_captureInProgress) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Capture already running...')),
      );
      return;
    }

    _captureInProgress = true;
    final useFlash = _flash == FlashSetting.on;
    final previousFanLevel = _fanLevel;
    int? restoreFanLevel;
    try {
      if (useFlash) {
        final fanPaused = await _setFanLevel(-1, showToast: false);
        if (fanPaused) {
          restoreFanLevel = previousFanLevel;
          if (mounted) setState(() => _fanLevel = -1);
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not pause fan for flash')),
          );
        }
        await _flashOnIfEnabled();
      }
      await _runStreamUsbScript();
    } finally {
      if (useFlash) {
        await _flashOff();
        if (restoreFanLevel != null && restoreFanLevel != -1) {
          final restored = await _setFanLevel(
            restoreFanLevel,
            showToast: false,
          );
          if (restored) {
            if (mounted) setState(() => _fanLevel = restoreFanLevel!);
          } else if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Failed to restore fan after flash'),
              ),
            );
          }
        }
      }
      _captureInProgress = false;
      if (_liveLoopEnabled) {
        // Resume live preview if it was active
        unawaited(_setLiveFlagInDb(true));
      }
    }
  }

  void _toggleSettings() => setState(() => _settingsOpen = !_settingsOpen);

  void _startLiveLoop() {
    if (_liveLoopEnabled) return;
    unawaited(_setLiveFlagInDb(true));
    setState(() {
      _liveLoopEnabled = true;
      // Legacy timer removed. C binary handles live preview now.
    });
  }

  void _stopLiveLoop() {
    _liveTimer?.cancel();
    _liveTimer = null;
    setState(() {
      _liveLoopEnabled = false;
      _liveTickInFlight = false;
    });
    unawaited(_setLiveFlagInDb(false));
  }

  void _toggleLiveLoop() {
    if (_liveLoopEnabled) {
      _stopLiveLoop();
    } else {
      _startLiveLoop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(child: LivePreview(projectRoot: _projectRoot)),

            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 24),
                child: ShutterButton(onPressed: _onCapturePressed),
              ),
            ),

            Align(
              alignment: Alignment.bottomLeft,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 16,
                    ),
                    minimumSize: const Size(72, 56),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: Icon(
                    _liveLoopEnabled ? Icons.stop : Icons.play_arrow,
                    size: 24,
                  ),
                  label: Text(_liveLoopEnabled ? 'Stop Live' : 'Start Live'),
                  onPressed: _toggleLiveLoop,
                ),
              ),
            ),

            Align(
              alignment: Alignment.bottomRight,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.all(16),
                    minimumSize: const Size(72, 72),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Icon(Icons.photo_library_outlined, size: 45),
                  onPressed: () async {
                    final root = await _locateProjectRoot();
                    if (context.mounted) {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder:
                              (_) => LibraryPage(
                                dirPath:
                                    root != null
                                        ? p.join(root, 'images')
                                        : 'images/',
                              ),
                        ),
                      );
                    }
                  },
                ),
              ),
            ),

            Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.exit_to_app, color: Colors.white, size: 32),
                      onPressed: () => exit(0),
                      tooltip: 'Quit Application',
                    ),
                    const SizedBox(height: 8),
                    Transform.scale(
                      scale: 1.5,
                      child: Switch(
                        value: _externalButtonEnabled,
                        onChanged: (value) {
                          setState(() {
                            _externalButtonEnabled = value;
                          });
                        },
                        activeColor: Colors.white,
                        activeTrackColor: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    BatteryIndicator(
                      iconSize: 20,
                      iconColor: Colors.white,
                      textColor: Colors.white,
                    ),
                    const SizedBox(height: 4),
                    IconButton(
                      tooltip: _settingsOpen
                          ? 'Close settings'
                          : 'Open settings',
                      icon: Icon(
                        _settingsOpen ? Icons.close : Icons.tune,
                        color: Colors.white,
                      ),
                      iconSize: 30,
                      onPressed: _toggleSettings,
                    ),
                  ],
                ),
              ),
            ),

            if (_settingsOpen)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _settingsOpen = false),
                  child: Container(color: Colors.black12),
                ),
              ),

            SettingsOverlay(
              open: _settingsOpen,
              flash: _flash,
              onFlashChanged: (v) => setState(() => _flash = v),
              onOpenLed: () => setState(() {
                _settingsOpen = false;
                _ledOpen = true;
              }),
              onOpenExposure: () => setState(() {
                _settingsOpen = false;
                _exposureOpen = true;
              }),
            ),

            if (_ledOpen)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _ledOpen = false),
                  child: Container(color: Colors.black26),
                ),
              ),

            if (_ledOpen)
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: false,
                  child: Container(
                    alignment: Alignment.center,
                    child: Material(
                      elevation: 12,
                      borderRadius: BorderRadius.circular(16),
                      color: Colors.white,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          minWidth: 280,
                          maxWidth: 360,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'LED options',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Close',
                                    icon: const Icon(Icons.close),
                                    iconSize: 30,
                                    onPressed: () =>
                                        setState(() => _ledOpen = false),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Center(
                                child: Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  alignment: WrapAlignment.center,
                                  runAlignment: WrapAlignment.center,
                                  children: [
                                    // FAN PWM cycling button (Low -> Med -> High -> Low)
                                    ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        minimumSize: const Size(110, 50),
                                        backgroundColor: _fanLevel < 0
                                            ? null
                                            : (_fanLevel == 0
                                                  ? Colors.lightBlue
                                                  : _fanLevel == 1
                                                  ? Colors.blue
                                                  : Colors.indigo),
                                      ),
                                      onPressed: () async {
                                        final next = _fanLevel < 0
                                            ? 0
                                            : (_fanLevel == 2
                                                  ? -1
                                                  : _fanLevel + 1);
                                        final ok = await _setFanLevel(next);
                                        if (ok && mounted) {
                                          setState(() => _fanLevel = next);
                                        }
                                      },
                                      icon: const Icon(Icons.toys),
                                      label: const Text('FAN'),
                                    ),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        minimumSize: const Size(110, 50),
                                      ),
                                      onPressed: () {
                                        _runLed('rainbow');
                                      },
                                      child: const Text('Rainbow'),
                                    ),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        minimumSize: const Size(110, 50),
                                      ),
                                      onPressed: () {
                                        _runLed('comet');
                                      },
                                      child: const Text('Comet'),
                                    ),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        minimumSize: const Size(110, 50),
                                      ),
                                      onPressed: () {
                                        _runLed('theater');
                                      },
                                      child: const Text('Theater'),
                                    ),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        minimumSize: const Size(110, 50),
                                      ),
                                      onPressed: () {
                                        _runLed('white');
                                      },
                                      child: const Text('White'),
                                    ),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        minimumSize: const Size(110, 50),
                                      ),
                                      onPressed: () {
                                        _runLed('clear');
                                      },
                                      child: const Text('Clear'),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            _buildExposureOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _buildExposureOverlay() {
    if (!_exposureOpen) return const SizedBox.shrink();

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _exposureOpen = false),
            child: Container(color: Colors.black26),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            ignoring: false,
            child: Container(
              alignment: Alignment.center,
              child: Material(
                elevation: 12,
                borderRadius: BorderRadius.circular(16),
                color: Colors.white,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: 280,
                    maxWidth: 360,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Exposure Control',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Close',
                              icon: const Icon(Icons.close),
                              iconSize: 30,
                              onPressed: () =>
                                  setState(() => _exposureOpen = false),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            const Text('1'),
                            Expanded(
                              child: Slider(
                                value: _exposureValue,
                                min: 1,
                                max: 10,
                                divisions: 9,
                                label: _exposureValue.round().toString(),
                                onChanged: (value) {
                                  setState(() => _exposureValue = value);
                                },
                              ),
                            ),
                            const Text('10'),
                          ],
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: _confirmExposure,
                          child: const Text('Confirm'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
