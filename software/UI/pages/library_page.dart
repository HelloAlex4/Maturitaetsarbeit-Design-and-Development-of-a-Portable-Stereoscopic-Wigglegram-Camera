/**
 * A majority of this code was written by AI.
 * 
 * Script Name: library_page.dart
 * Description: 
 *   Image gallery page for browsing captured photos and GIFs. Supports 
 *   fullscreen viewing, deletion, and exporting selected files to
 *   external USB drives.
 */

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show ImageByteFormat; // Rect/Size not used here

import 'package:flutter/material.dart';
import 'package:flutter/painting.dart' show PaintingBinding;
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/foundation.dart';
import 'dart:ui' as ui;

import '../widgets/battery_indicator.dart';
import 'focus_sequence_page.dart';

class LibraryPage extends StatefulWidget {
  final String dirPath;
  const LibraryPage({super.key, required this.dirPath});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  bool _isFullscreen = false; // kept for compatibility; no button to toggle
  bool _loading = true;
  final ScrollController _scrollCtrl = ScrollController();
  final List<File> _files = <File>[];
  int _visibleCount = 0;

  final Map<String, Uint8List> _gifFirstFrameCache = <String, Uint8List>{};

  // Export selection state
  bool _selectingForExport = false;
  final Set<String> _selectedExport = <String>{};

  // final RegExp _seriesRe = RegExp(r'^(.*)_([1-4])(\.[^.]+)$', caseSensitive: false);

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    _reload();
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _files.clear();
      _visibleCount = 0;
    });
    final dir = Directory(widget.dirPath);
    if (!await dir.exists()) {
      try {
        await dir.create(recursive: true);
      } catch (_) {}
    }
    final List<FileSystemEntity> entries = await dir.list().toList();
    final List<File> imgs = entries.whereType<File>().where((f) {
      final lp = f.path.toLowerCase();
      return lp.endsWith('.jpg') ||
          lp.endsWith('.jpeg') ||
          lp.endsWith('.png') ||
          lp.endsWith('.gif');
    }).toList();

    final List<File> filtered = imgs;

    int _leadingNumberFromPath(String path) {
      final String name = p.basename(path);
      final match = RegExp(r'^(\d+)').firstMatch(name);
      if (match != null) {
        return int.tryParse(match.group(1)!) ?? -1;
      }
      return -1; // non-numeric names sort last
    }

    // Sort by leading number in filename (descending), then by path as tiebreaker
    filtered.sort((a, b) {
      final int an = _leadingNumberFromPath(a.path);
      final int bn = _leadingNumberFromPath(b.path);
      final int cmpNum = bn.compareTo(an); // descending
      if (cmpNum != 0) return cmpNum;
      return a.path.compareTo(b.path); // stable tiebreaker
    });

    setState(() {
      _files.addAll(filtered);
      _loading = false;
      _visibleCount = (_files.length < 24) ? _files.length : 24;
    });
  }

  void _onScroll() {
    if (!_scrollCtrl.hasClients || _loading) return;
    final pos = _scrollCtrl.position;
    if (pos.pixels > pos.maxScrollExtent - 600) {
      final int add = 24;
      if (_visibleCount < _files.length) {
        setState(() {
          _visibleCount = (_visibleCount + add).clamp(0, _files.length);
        });
      }
    }
  }

  void _evictImageCacheFor(String path) {
    try {
      final provider = FileImage(File(path));
      PaintingBinding.instance.imageCache.evict(provider);
      PaintingBinding.instance.imageCache.clearLiveImages();
    } catch (_) {}
  }

  // _deleteRawsForBase removed (unused private helper)

  // _deleteFile removed (unused private helper)

  Future<Uint8List?> _loadGifFirstFrame(File file, int targetPx) async {
    final key = file.path;
    final cached = _gifFirstFrameCache[key];
    if (cached != null) return cached;

    try {
      final raw = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(
        raw,
        targetWidth: targetPx,
        targetHeight: targetPx,
      );
      final frame = await codec.getNextFrame();
      final ui.Image img = frame.image;
      final byteData = await img.toByteData(format: ImageByteFormat.png);
      final bytes = byteData?.buffer.asUint8List();
      if (bytes != null) {
        _gifFirstFrameCache[key] = bytes;
      }
      return bytes;
    } catch (_) {
      return null;
    }
  }

  Future<void> _toggleFullscreen() async {
    setState(() => _isFullscreen = !_isFullscreen);
    if (_isFullscreen) {
      try {
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      } catch (_) {}
    } else {
      try {
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      } catch (_) {}
    }
  }

  void _startExportSelection() {
    setState(() {
      _selectingForExport = true;
      _selectedExport.clear();
    });
  }

  void _cancelExportSelection() {
    setState(() {
      _selectingForExport = false;
      _selectedExport.clear();
    });
  }

  void _toggleExportPick(String path) {
    setState(() {
      if (_selectedExport.contains(path)) {
        _selectedExport.remove(path);
      } else {
        _selectedExport.add(path);
      }
    });
  }

  void _selectAllVisibleForExport() {
    setState(() {
      _selectedExport
        ..clear()
        ..addAll(_files.take(_visibleCount).map((f) => f.path));
    });
  }

  Future<String> _resolveRawExtForBase(String base) async {
    final String rawsDir = p.join(widget.dirPath, 'raws');
    for (final String ext in ['.jpg', '.jpeg', '.png']) {
      final f = File(p.join(rawsDir, '${base}_1$ext'));
      if (await f.exists()) return ext;
    }
    return '.jpg';
  }

  Future<List<String>> _expandSelectionToRawPaths(Set<String> selected) async {
    final Set<String> toCopy = <String>{};
    for (final path in selected) {
      final lower = path.toLowerCase();
      if (lower.endsWith('.gif')) {
        toCopy.add(path);
        continue;
      }
      final name = p.basename(path);
      final match = RegExp(r'^(.*)_([1-4])(\.[^.]+)$').firstMatch(name);
      if (match != null) {
        final base = match.group(1)!;
        final String rawExt = await _resolveRawExtForBase(base);
        final String rawsDir = p.join(widget.dirPath, 'raws');
        bool anyRawFound = false;
        for (int i = 1; i <= 4; i++) {
          final rawPath = p.join(rawsDir, '${base}_$i$rawExt');
          if (File(rawPath).existsSync()) {
            toCopy.add(rawPath);
            anyRawFound = true;
          }
        }
        if (!anyRawFound) {
          final dir = p.dirname(path);
          final ext = match.group(3)!;
          for (int i = 1; i <= 4; i++) {
            final cand = p.join(dir, '${base}_$i$ext');
            if (File(cand).existsSync()) toCopy.add(cand);
          }
        }
      } else {
        toCopy.add(path);
      }
    }
    return toCopy.toList();
  }

  Future<List<Directory>> _findExternalDrives() async {
    final List<Directory> drives = [];
    bool _isRootFsDir(Directory d) {
      final name = p.basename(d.path.replaceAll(RegExp(r'[\\/]+$'), ''));
      return name.toLowerCase() == 'rootfs';
    }

    try {
      if (Platform.isMacOS) {
        final root = Directory('/Volumes');
        if (await root.exists()) {
          for (final e in root.listSync()) {
            if (e is Directory) {
              if (_isRootFsDir(e)) continue;
              drives.add(e);
            }
          }
        }
      } else if (Platform.isLinux) {
        final candidates = <String>['/media', '/run/media', '/mnt'];
        for (final c in candidates) {
          final d = Directory(c);
          if (!d.existsSync()) continue;
          for (final e in d.listSync(recursive: false)) {
            if (e is Directory) {
              // Many distros mount as /media/<user>/<label>
              final subs = e.listSync(recursive: false);
              if (subs.isEmpty) {
                if (_isRootFsDir(e)) continue;
                drives.add(e);
              } else {
                for (final s in subs) {
                  if (s is Directory) {
                    if (_isRootFsDir(s)) continue;
                    drives.add(s);
                  }
                }
              }
            }
          }
        }
      } else if (Platform.isWindows) {
        for (int i = 67; i <= 90; i++) {
          // C..Z
          final letter = String.fromCharCode(i);
          final dir = Directory('$letter:\\');
          if (dir.existsSync()) drives.add(dir);
        }
      }
    } catch (_) {}
    // Deduplicate by resolved path
    final seen = <String>{};
    final unique = <Directory>[];
    for (final d in drives) {
      final path = d.path;
      if (seen.add(path)) unique.add(d);
    }
    return unique;
  }

  Future<Directory?> _promptDestination() async {
    final drives = await _findExternalDrives();
    return showDialog<Directory>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Select destination drive'),
          content: SizedBox(
            width: 480,
            height: 320,
            child: drives.isEmpty
                ? const Center(
                    child: Text(
                      'No external drives found. Connect a drive and try again.',
                    ),
                  )
                : ListView.builder(
                    itemCount: drives.length,
                    itemBuilder: (c, i) {
                      final d = drives[i];
                      return ListTile(
                        leading: const Icon(Icons.usb),
                        title: Text(d.path),
                        onTap: () => Navigator.of(ctx).pop(d),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _exportSelected() async {
    if (_selectedExport.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No images selected.')));
      return;
    }
    final sources = await _expandSelectionToRawPaths(_selectedExport);
    if (sources.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No files found to export.')),
      );
      return;
    }
    final dest = await _promptDestination();
    if (dest == null) return;

    int completed = 0;
    final total = sources.length;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        bool started = false;
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            Future<void> runOnce() async {
              // Run copy asynchronously after first frame
              await Future<void>.delayed(const Duration(milliseconds: 10));
              for (final path in sources) {
                try {
                  final src = File(path);
                  if (!await src.exists()) continue;
                  final base = p.basename(src.path);
                  String destPath = p.join(dest.path, base);
                  // Avoid overwriting: add (n) suffix
                  if (await File(destPath).exists()) {
                    final name = p.basenameWithoutExtension(base);
                    final ext = p.extension(base);
                    int n = 1;
                    while (await File(
                      p.join(dest.path, '$name ($n)$ext'),
                    ).exists()) {
                      n++;
                    }
                    destPath = p.join(dest.path, '$name ($n)$ext');
                  }
                  await src.copy(destPath);
                } catch (_) {}
                completed++;
                setLocal(() {});
              }
              if (ctx.mounted) Navigator.of(ctx).pop();
            }

            // Trigger copy exactly once
            if (!started) {
              started = true;
              unawaited(runOnce());
            }

            final progress = total == 0
                ? 0.0
                : (completed / total).clamp(0.0, 1.0);
            return AlertDialog(
              title: const Text('Exporting images...'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LinearProgressIndicator(value: total > 0 ? progress : null),
                  const SizedBox(height: 12),
                  Text('$completed / $total'),
                ],
              ),
            );
          },
        );
      },
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Export complete: $completed / $total files.')),
    );
    _cancelExportSelection();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _isFullscreen
          ? null
          : AppBar(
              title: Text('Library: ${widget.dirPath}'),
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
                  tooltip: 'Refresh',
                  iconSize: 28,
                  onPressed: _reload,
                  icon: const Icon(Icons.refresh),
                ),
                IconButton(
                  tooltip: _selectingForExport ? 'Cancel export' : 'Export',
                  iconSize: 28,
                  onPressed: _selectingForExport
                      ? _cancelExportSelection
                      : _startExportSelection,
                  icon: Icon(
                    _selectingForExport
                        ? Icons.close
                        : Icons.file_upload_outlined,
                  ),
                ),
              ],
            ),
      body: SafeArea(
        top: _isFullscreen ? false : true,
        bottom: _isFullscreen ? false : true,
        left: true,
        right: true,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : (_files.isEmpty
                  ? const Center(child: Text('No images found.'))
                  : Builder(
                      builder: (context) {
                        const double _gridPadding = 12.0;
                        const double _gridSpacing = 12.0;
                        const int _crossAxisCount = 3;
                        final double gridWidth =
                            MediaQuery.of(context).size.width -
                            (_gridPadding * 2);
                        final double cellLogical =
                            (gridWidth - _gridSpacing * (_crossAxisCount - 1)) /
                            _crossAxisCount;
                        final double dpr = MediaQuery.of(
                          context,
                        ).devicePixelRatio;
                        final int targetPx = (cellLogical * dpr).round();

                        return GridView.builder(
                          controller: _scrollCtrl,
                          padding: const EdgeInsets.all(12),
                          cacheExtent: cellLogical * 3,
                          physics: const AlwaysScrollableScrollPhysics(),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                mainAxisSpacing: 12,
                                crossAxisSpacing: 12,
                              ),
                          itemCount: _visibleCount,
                          itemBuilder: (context, index) {
                            final file = _files[index];
                            final isGif = file.path.toLowerCase().endsWith(
                              '.gif',
                            );
                            if (isGif) {
                              return AspectRatio(
                                aspectRatio: 1,
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    Container(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color:
                                              _selectedExport.contains(
                                                file.path,
                                              )
                                              ? Colors.blueAccent
                                              : Colors.transparent,
                                          width: 3,
                                        ),
                                      ),
                                    ),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: GestureDetector(
                                        onTap: () async {
                                          if (_selectingForExport) {
                                            _toggleExportPick(file.path);
                                            return;
                                          }
                                          final res =
                                              await Navigator.of(context).push(
                                                MaterialPageRoute(
                                                  builder: (_) =>
                                                      _FullImageView.withArgs(
                                                        _files
                                                            .map((f) => f.path)
                                                            .toList(),
                                                        index,
                                                        widget.dirPath,
                                                      ),
                                                ),
                                              );
                                          if (res == 'deleted') {
                                            await _reload();
                                          } else if (res is String &&
                                              res.startsWith('updated:')) {
                                            final String updatedPath = res
                                                .substring('updated:'.length);
                                            _evictImageCacheFor(updatedPath);
                                            _gifFirstFrameCache.remove(
                                              updatedPath,
                                            );
                                            await _reload();
                                          }
                                        },
                                        child: FutureBuilder<Uint8List?>(
                                          future: _loadGifFirstFrame(
                                            file,
                                            targetPx + 50,
                                          ),
                                          builder: (context, snap) {
                                            if (snap.hasData &&
                                                snap.data != null) {
                                              return SizedBox.expand(
                                                child: Image.memory(
                                                  snap.data!,
                                                  fit: BoxFit.cover,
                                                  filterQuality:
                                                      FilterQuality.low,
                                                  isAntiAlias: true,
                                                  gaplessPlayback: true,
                                                ),
                                              );
                                            }
                                            return const ColoredBox(
                                              color: Colors.black12,
                                              child: Center(
                                                child:
                                                    CircularProgressIndicator(),
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                                    if (_selectingForExport)
                                      Positioned(
                                        top: 6,
                                        right: 6,
                                        child: _SelectionCheck(
                                          checked: _selectedExport.contains(
                                            file.path,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            } else {
                              return AspectRatio(
                                aspectRatio: 1,
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    Container(
                                      decoration: BoxDecoration(
                                        border: Border.all(
                                          color:
                                              _selectedExport.contains(
                                                file.path,
                                              )
                                              ? Colors.blueAccent
                                              : Colors.red,
                                          width:
                                              _selectedExport.contains(
                                                file.path,
                                              )
                                              ? 3
                                              : 2,
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: SizedBox.expand(
                                          child: Image.file(
                                            file,
                                            fit: BoxFit.cover,
                                            cacheWidth: targetPx + 50,
                                            filterQuality: FilterQuality.low,
                                            isAntiAlias: true,
                                            gaplessPlayback: true,
                                            errorBuilder: (ctx, err, st) =>
                                                const ColoredBox(
                                                  color: Colors.black12,
                                                  child: Center(
                                                    child: Icon(
                                                      Icons
                                                          .broken_image_outlined,
                                                    ),
                                                  ),
                                                ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    // Tap overlay for fullscreen view
                                    Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        onTap: () async {
                                          if (_selectingForExport) {
                                            _toggleExportPick(file.path);
                                            return;
                                          }
                                          final res =
                                              await Navigator.of(context).push(
                                                MaterialPageRoute(
                                                  builder: (_) =>
                                                      _FullImageView.withArgs(
                                                        _files
                                                            .map((f) => f.path)
                                                            .toList(),
                                                        index,
                                                        widget.dirPath,
                                                      ),
                                                ),
                                              );
                                          if (res == 'deleted') {
                                            await _reload();
                                          } else if (res is String &&
                                              res.startsWith('updated:')) {
                                            final String updatedPath = res
                                                .substring('updated:'.length);
                                            _evictImageCacheFor(updatedPath);
                                            _gifFirstFrameCache.remove(
                                              updatedPath,
                                            );
                                            await _reload();
                                          }
                                        },
                                      ),
                                    ),
                                    if (_selectingForExport)
                                      Positioned(
                                        top: 6,
                                        right: 6,
                                        child: _SelectionCheck(
                                          checked: _selectedExport.contains(
                                            file.path,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            }
                          },
                        );
                      },
                    )),
      ),
      // Remove fullscreen floating action button
      floatingActionButton: null,
      bottomNavigationBar: _selectingForExport
          ? SafeArea(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  boxShadow: const [
                    BoxShadow(blurRadius: 6, color: Colors.black26),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${_selectedExport.length} selected',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    TextButton(
                      onPressed: _selectAllVisibleForExport,
                      child: const Text('Select All'),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: _cancelExportSelection,
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: _selectedExport.isEmpty
                          ? null
                          : _exportSelected,
                      icon: const Icon(Icons.file_upload_outlined),
                      label: const Text('Export'),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }
}

class _SelectionCheck extends StatelessWidget {
  final bool checked;
  const _SelectionCheck({required this.checked});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: checked ? Colors.blueAccent : Colors.white70,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.black26),
      ),
      padding: const EdgeInsets.all(2),
      child: Icon(
        checked ? Icons.check : Icons.circle_outlined,
        size: 18,
        color: checked ? Colors.white : Colors.black54,
      ),
    );
  }
}

class _FullImageView extends StatefulWidget {
  final List<String> paths;
  final int initialIndex;
  final String rootDir;
  static Widget withArgs(
    List<String> paths,
    int initialIndex,
    String rootDir,
  ) => _FullImageView(
    paths: paths,
    initialIndex: initialIndex,
    rootDir: rootDir,
  );

  const _FullImageView({
    required this.paths,
    required this.initialIndex,
    required this.rootDir,
  });

  @override
  State<_FullImageView> createState() => __FullImageViewState();
}

class __FullImageViewState extends State<_FullImageView> {
  bool _confirmingDelete = false;

  Future<String> _resolveRawExt(String base) async {
    final String rawsDir = p.join(widget.rootDir, 'raws');
    for (final String ext in ['.jpg', '.jpeg', '.png']) {
      final f = File(p.join(rawsDir, '${base}_1$ext'));
      if (await f.exists()) return ext;
    }
    return '.jpg';
  }

  Future<void> _deleteRawsForBase(String base) async {
    final String rawsDir = p.join(widget.rootDir, 'raws');
    final String resolvedExt = await _resolveRawExt(base);
    final List<String> exts = ['.jpg', '.jpeg', '.png'];
    final List<String> tryExts = [
      resolvedExt,
      ...exts.where((e) => e != resolvedExt),
    ];
    for (final String ext in tryExts) {
      for (int i = 1; i <= 4; i++) {
        final f = File(p.join(rawsDir, '${base}_$i$ext'));
        if (await f.exists()) {
          try {
            await f.delete();
          } catch (_) {}
        }
      }
    }
  }

  Future<void> _deleteCurrent() async {
    final path = widget.paths[_index];
    final file = File(path);
    try {
      final name = p.basename(file.path);
      final match = RegExp(r'^(.*)_([1-4])(\.[^.]+)$').firstMatch(name);
      if (match != null) {
        final String base = match.group(1)!;
        final String ext = match.group(3)!;
        final dir = p.dirname(file.path);
        for (int i = 1; i <= 4; i++) {
          final f = File(p.join(dir, '${base}_$i$ext'));
          if (await f.exists()) {
            try {
              await f.delete();
            } catch (_) {}
          }
        }
        final gif = File(p.join(dir, '$base.gif'));
        if (await gif.exists()) {
          try {
            await gif.delete();
          } catch (_) {}
        }
        await _deleteRawsForBase(base);
      } else {
        if (await file.exists()) {
          await file.delete();
        }
      }
      if (name.toLowerCase().endsWith('.gif')) {
        final int dot = name.lastIndexOf('.');
        final String base = dot > 0 ? name.substring(0, dot) : name;
        await _deleteRawsForBase(base);
      }
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).pop('deleted');
  }

  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.paths.length - 1);
    _evictCurrent();
  }

  void _evictCurrent() {
    try {
      final provider = FileImage(File(widget.paths[_index]));
      PaintingBinding.instance.imageCache.evict(provider);
      PaintingBinding.instance.imageCache.clearLiveImages();
    } catch (_) {}
  }

  void _prev() {
    if (_index > 0) {
      setState(() => _index--);
      _evictCurrent();
    }
  }

  void _next() {
    if (_index < widget.paths.length - 1) {
      setState(() => _index++);
      _evictCurrent();
    }
  }

  @override
  Widget build(BuildContext context) {
    final path = widget.paths[_index];
    final String lower = path.toLowerCase();
    final bool isGif = lower.endsWith('.gif');
    final bool hasPrev = _index > 0;
    final bool hasNext = _index < widget.paths.length - 1;
    // Resolve fallback if a .gif path is missing: try <base>_1.(jpg|jpeg|png)
    String _resolvedForDisplay(String pth) {
      if (!pth.toLowerCase().endsWith('.gif')) return pth;
      final f = File(pth);
      if (f.existsSync()) return pth;
      final dir = p.dirname(pth);
      final base = p.basenameWithoutExtension(pth);
      for (final ext in const ['.jpg', '.jpeg', '.png']) {
        final cand = File(p.join(dir, base + '_1' + ext));
        if (cand.existsSync()) return cand.path;
      }
      // Also try images/raws as a last resort
      for (final ext in const ['.jpg', '.jpeg', '.png']) {
        final cand = File(p.join(widget.rootDir, 'raws', base + '_1' + ext));
        if (cand.existsSync()) return cand.path;
      }
      return pth; // fall back to original (may error, but nothing better)
    }

    final String displayPath = _resolvedForDisplay(path);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: InteractiveViewer(
              child: () {
                final f = File(displayPath);
                if (f.existsSync()) {
                  return Image.file(f, fit: BoxFit.contain);
                }
                return const Center(
                  child: Icon(
                    Icons.broken_image_outlined,
                    color: Colors.white54,
                    size: 72,
                  ),
                );
              }(),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Material(
                color: Colors.black45,
                shape: const CircleBorder(),
                child: IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.bottomRight,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Material(
                  color: Colors.black45,
                  shape: const CircleBorder(),
                  child: IconButton(
                    tooltip: 'Delete',
                    icon: const Icon(Icons.delete, color: Colors.white),
                    onPressed: () => setState(() => _confirmingDelete = true),
                  ),
                ),
              ),
            ),
          ),
          if (_confirmingDelete)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _confirmingDelete = false),
                child: Container(color: Colors.transparent),
              ),
            ),
          if (_confirmingDelete)
            SafeArea(
              child: Align(
                alignment: Alignment.bottomRight,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 72),
                  child: Material(
                    elevation: 8,
                    borderRadius: BorderRadius.circular(8),
                    color: Colors.black54,
                    child: IntrinsicWidth(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'Delete this image/group?',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton(
                                  onPressed: () =>
                                      setState(() => _confirmingDelete = false),
                                  child: const Text('Cancel'),
                                ),
                                const SizedBox(width: 4),
                                TextButton(
                                  onPressed: () async {
                                    setState(() => _confirmingDelete = false);
                                    await _deleteCurrent();
                                  },
                                  child: const Text(
                                    'Delete',
                                    style: TextStyle(color: Colors.redAccent),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Opacity(
                opacity: hasPrev ? 1.0 : 0.3,
                child: Material(
                  color: Colors.black38,
                  shape: const CircleBorder(),
                  child: IconButton(
                    iconSize: 40,
                    icon: const Icon(Icons.chevron_left, color: Colors.white),
                    onPressed: hasPrev ? _prev : null,
                    tooltip: 'Previous',
                  ),
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Opacity(
                opacity: hasNext ? 1.0 : 0.3,
                child: Material(
                  color: Colors.black38,
                  shape: const CircleBorder(),
                  child: IconButton(
                    iconSize: 40,
                    icon: const Icon(Icons.chevron_right, color: Colors.white),
                    onPressed: hasNext ? _next : null,
                    tooltip: 'Next',
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.movie_creation_outlined),
                    label: Text(
                      isGif ? 'Edit GIF' : 'Convert to GIF',
                      textAlign: TextAlign.center,
                    ),
                    onPressed: () async {
                      final dir = p.dirname(path);
                      final name = p.basename(path);
                      String base;
                      String ext;
                      if (!isGif) {
                        final m = RegExp(
                          r'^(.*)_([1-4])(\.[^.]+)$',
                        ).firstMatch(name);
                        if (m != null) {
                          base = m.group(1)!;
                          ext = m.group(3)!;
                        } else {
                          final dot = name.lastIndexOf('.');
                          if (dot > 0) {
                            base = name.substring(0, dot);
                            ext = name.substring(dot);
                          } else {
                            base = name;
                            ext = '';
                          }
                        }
                      } else {
                        final dot = name.lastIndexOf('.');
                        base = (dot > 0) ? name.substring(0, dot) : name;
                        ext = await _resolveRawExt(base);
                      }

                      if (!mounted) return;
                      final res = await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => FocusSequencePage(
                            dirPath: dir,
                            baseName: base,
                            extWithDot: ext,
                          ),
                        ),
                      );
                      if (!mounted) return;
                      if (res is String && res.startsWith('updated:')) {
                        final String updatedPath = res.substring(
                          'updated:'.length,
                        );
                        // Only update if the new path actually exists
                        if (!File(updatedPath).existsSync()) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'GIF not found; keeping original image.',
                              ),
                            ),
                          );
                          return;
                        }
                        try {
                          PaintingBinding.instance.imageCache.clear();
                          PaintingBinding.instance.imageCache.clearLiveImages();
                          try {
                            final providerOld = FileImage(
                              File(widget.paths[_index]),
                            );
                            PaintingBinding.instance.imageCache.evict(
                              providerOld,
                            );
                          } catch (_) {}
                          try {
                            final providerNew = FileImage(File(updatedPath));
                            PaintingBinding.instance.imageCache.evict(
                              providerNew,
                            );
                          } catch (_) {}
                        } catch (_) {}
                        setState(() {
                          widget.paths[_index] = updatedPath;
                        });
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('GIF updated.')),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
