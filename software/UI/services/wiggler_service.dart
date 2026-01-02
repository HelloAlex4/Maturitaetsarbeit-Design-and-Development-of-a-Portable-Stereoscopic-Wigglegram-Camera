/**
 * A majority of this code was written by AI.
 * 
 * Script Name: wiggler_service.dart
 * Description: 
 *   Service wrapper for executing the `wiggler.py` Python script. 
 *   Orchestrates the image alignment and GIF creation pipeline.
 */

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

Future<int> fullFunction(
  String filename,
  List<int> focus1,
  List<int> focus2,
  List<int> focus3,
  List<int> focus4,
  int speed,
  String? imagesDir,
) async {
  const String _pythonExec = 'python3';
  const String _wigglerScriptRel = 'scripts/wiggler.py';

  Future<String?> _findInParents(
    String relativePath, {
    int maxLevels = 8,
  }) async {
    // 1) Direct relative
    final direct = File(relativePath);
    if (await direct.exists()) return direct.absolute.path;

    // 2) From CWD
    final cwd = Directory.current.path;
    final fromCwd = File(p.join(cwd, relativePath));
    if (await fromCwd.exists()) return fromCwd.absolute.path;

    // 3) From executable dir
    final execDir = Directory(p.dirname(Platform.resolvedExecutable));
    final fromExec = File(p.join(execDir.path, relativePath));
    if (await fromExec.exists()) return fromExec.absolute.path;

    // 4) From exec parent
    final fromExecParent = File(p.join(execDir.parent.path, relativePath));
    if (await fromExecParent.exists()) return fromExecParent.absolute.path;

    // 5) Walk up parents from CWD
    Directory probe = Directory(cwd);
    for (int i = 0; i < maxLevels; i++) {
      final candidate = File(p.join(probe.path, relativePath));
      if (await candidate.exists()) return candidate.absolute.path;
      final next = probe.parent;
      if (next.path == probe.path) break;
      probe = next;
    }
    return null;
  }

  // Locate the Python script robustly and use absolute paths
  final String? scriptPath = await _findInParents(_wigglerScriptRel);
  if (scriptPath == null) {
    // ignore: avoid_print
    print(
      'wiggler.py not found relative to app. Looked for: $_wigglerScriptRel',
    );
    return -1;
  }

  // Validate focuses: ensure 2-length lists
  List<int> _xy(List<int> v) => v.length >= 2 ? v : <int>[0, 0];
  final List<int> f1 = _xy(focus1);
  final List<int> f2 = _xy(focus2);
  final List<int> f3 = _xy(focus3);
  final List<int> f4 = _xy(focus4);

  // Use unbuffered Python (-u) so logs flush immediately; stream output live
  final List<String> args = <String>[
    '-u',
    scriptPath,
    filename,
    f1[0].toString(),
    f1[1].toString(),
    f2[0].toString(),
    f2[1].toString(),
    f3[0].toString(),
    f3[1].toString(),
    f4[0].toString(),
    f4[1].toString(),
    '--speed',
    speed.toString(),
  ];
  if (imagesDir != null) {
    args.addAll(['--images-dir', imagesDir]);
  }

  String _signalName(int sig) {
    switch (sig) {
      case 1:
        return 'SIGHUP';
      case 2:
        return 'SIGINT';
      case 9:
        return 'SIGKILL';
      case 11:
        return 'SIGSEGV';
      case 15:
        return 'SIGTERM';
      default:
        return 'SIG$sig';
    }
  }

  try {
    final env = Map<String, String>.from(Platform.environment);
    env['PYTHONUNBUFFERED'] = '1';

    // Prefer running from project root (parent of scripts)
    final String workDir = Directory(p.dirname(p.dirname(scriptPath))).path;
    // Log the exact command for debug visibility
    // ignore: avoid_print
    print('Running: $_pythonExec ${args.join(' ')} (cwd: $workDir)');

    final Process proc = await Process.start(
      _pythonExec,
      args,
      environment: env,
      workingDirectory: workDir,
    );

    // Stream stdout
    unawaited(
      proc.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            // ignore: avoid_print
            print('[wiggler.py][out] $line');
          })
          .asFuture(),
    );

    // Stream stderr
    unawaited(
      proc.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            // ignore: avoid_print
            print('[wiggler.py][err] $line');
          })
          .asFuture(),
    );

    final int code = await proc.exitCode;
    if (code != 0) {
      // Negative codes on Unix indicate termination by signal
      if (code < 0) {
        final sig = -code;
        // ignore: avoid_print
        print('[wiggler.py terminated by ${_signalName(sig)} ($sig)]');
      } else {
        // ignore: avoid_print
        print('[wiggler.py exit $code]');
      }
    } else {
      // ignore: avoid_print
      print('[wiggler.py exit 0]');
    }
    return code;
  } on ProcessException catch (e) {
    // ignore: avoid_print
    print('Failed to start wiggler.py: ${e.message}');
    return -1;
  }
}
