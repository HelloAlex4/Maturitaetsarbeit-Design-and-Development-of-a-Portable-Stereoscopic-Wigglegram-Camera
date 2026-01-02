/**
 * A majority of this code was written by AI.
 * 
 * Script Name: focus_sequence_page.dart
 * Description: 
 *   An interactive tool for aligning focus across multiple frames. Users 
 *   select common anchor points in a 4-frame sequence to prepare for 
 *   wiggle GIF generation.
 */

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show Rect, Size;

import 'package:flutter/material.dart';
import 'package:flutter/painting.dart' show PaintingBinding;
import 'package:path/path.dart' as p;

import '../services/wiggler_service.dart';
import '../widgets/battery_indicator.dart';

class FocusSequencePage extends StatefulWidget {
  final String dirPath;
  final String baseName;
  final String extWithDot;
  const FocusSequencePage({
    super.key,
    required this.dirPath,
    required this.baseName,
    required this.extWithDot,
  });

  @override
  State<FocusSequencePage> createState() => _FocusSequencePageState();
}

class _FocusSequencePageState extends State<FocusSequencePage> {
  int _index = 0;
  final List<List<int>?> _focuses = [null, null, null, null];
  int? _imgW;
  int? _imgH;
  int? _origW;
  int? _origH;
  int _orient = 1;

  late final List<String> _paths = List<String>.generate(
    4,
    (i) => [
      p.join(widget.dirPath, 'raws'),
      '${widget.baseName}_${i + 1}${widget.extWithDot}',
    ].join(Platform.pathSeparator),
  );

  bool _aimMode = false;
  int? _aimX;
  int? _aimY;
  static const int _nudgeStep = 10;
  static const double _zoomScale = 2.0;

  bool _zoomMode = false;
  double _zoomOffsetX = 0;
  double _zoomOffsetY = 0;

  @override
  void initState() {
    super.initState();
    _prepareCurrent();
  }

  Future<void> _prepareCurrent() async {
    _imgW = null;
    _imgH = null;
    final pth = _paths[_index];
    final file = File(pth);
    if (!await file.exists()) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Missing file: ${file.path}')));
      return;
    }
    await _readOriginalSizeAndOrientation(file);
    final ImageProvider provider = FileImage(file);
    final ImageStream stream = provider.resolve(const ImageConfiguration());
    late ImageStreamListener listener;
    listener = ImageStreamListener(
      (ImageInfo info, bool sync) {
        if (!mounted) return;
        setState(() {
          _imgW = info.image.width;
          _imgH = info.image.height;
        });
        stream.removeListener(listener);
      },
      onError: (Object _, StackTrace? __) {
        if (!mounted) return;
        setState(() {
          _imgW = null;
          _imgH = null;
        });
        stream.removeListener(listener);
      },
    );
    stream.addListener(listener);
  }

  Future<void> _readOriginalSizeAndOrientation(File f) async {
    _origW = null;
    _origH = null;
    _orient = 1;
    final bytes = await f.readAsBytes();
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      if (bytes.length >= 33 &&
          bytes[12] == 0x49 &&
          bytes[13] == 0x48 &&
          bytes[14] == 0x44 &&
          bytes[15] == 0x52) {
        final w =
            (bytes[16] << 24) |
            (bytes[17] << 16) |
            (bytes[18] << 8) |
            bytes[19];
        final h =
            (bytes[20] << 24) |
            (bytes[21] << 16) |
            (bytes[22] << 8) |
            bytes[23];
        _origW = w;
        _origH = h;
      }
      return;
    }
    int i = 0;
    bool seenSOI = false;
    int? sofW;
    int? sofH;
    while (i + 3 < bytes.length) {
      if (bytes[i] == 0xFF && bytes[i + 1] == 0xD8) {
        seenSOI = true;
        i += 2;
        continue;
      }
      if (!seenSOI) {
        i++;
        continue;
      }
      if (bytes[i] != 0xFF) {
        i++;
        continue;
      }
      int marker = bytes[i + 1];
      i += 2;
      if (marker == 0xD9 || marker == 0xDA) break;
      if (i + 1 >= bytes.length) break;
      int len = (bytes[i] << 8) | bytes[i + 1];
      i += 2;
      if (i + len - 2 > bytes.length) break;
      if (marker == 0xE1 && len >= 8) {
        final start = i;
        if (start + 6 <= bytes.length &&
            bytes[start] == 0x45 &&
            bytes[start + 1] == 0x78 &&
            bytes[start + 2] == 0x69 &&
            bytes[start + 3] == 0x66 &&
            bytes[start + 4] == 0x00 &&
            bytes[start + 5] == 0x00) {
          final tiff = start + 6;
          if (tiff + 8 <= bytes.length) {
            final bool little = bytes[tiff] == 0x49 && bytes[tiff + 1] == 0x49;
            int rd16(int off) => little
                ? (bytes[off] | (bytes[off + 1] << 8))
                : ((bytes[off] << 8) | bytes[off + 1]);
            int rd32(int off) => little
                ? (bytes[off] |
                      (bytes[off + 1] << 8) |
                      (bytes[off + 2] << 16) |
                      (bytes[off + 3] << 24))
                : ((bytes[off] << 24) |
                      (bytes[off + 1] << 16) |
                      (bytes[off + 2] << 8) |
                      bytes[off + 3]);
            final int ifd0Off = rd32(tiff + 4) + tiff;
            if (ifd0Off + 2 <= bytes.length) {
              final int n = rd16(ifd0Off);
              int base = ifd0Off + 2;
              for (int k = 0; k < n; k++) {
                if (base + 12 > bytes.length) break;
                final int tag = rd16(base);
                final int valueOff = base + 8;
                if (tag == 0x0112) {
                  final int val = rd16(valueOff);
                  if (val >= 1 && val <= 8) _orient = val;
                }
                base += 12;
              }
            }
          }
        }
      }
      if (marker == 0xC0 || marker == 0xC1 || marker == 0xC2) {
        if (len >= 7) {
          final int p0 = i;
          final int h = (bytes[p0 + 1] << 8) | bytes[p0 + 2];
          final int w = (bytes[p0 + 3] << 8) | bytes[p0 + 4];
          sofW = w;
          sofH = h;
        }
      }
      i += (len - 2);
    }
    if (sofW != null && sofH != null) {
      _origW = sofW;
      _origH = sofH;
    }
  }

  List<int> _mapRenderedToOriginal(
    int xr,
    int yr,
    int renderedW,
    int renderedH,
  ) {
    final int ow = _origW ?? renderedW;
    final int oh = _origH ?? renderedH;

    final double u = xr / renderedW;
    final double v = yr / renderedH;

    double xo;
    double yo;

    switch (_orient) {
      case 3:
        xo = (1.0 - u) * ow;
        yo = (1.0 - v) * oh;
        break;
      case 6:
        xo = v * ow;
        yo = (1.0 - u) * oh;
        break;
      case 8:
        xo = (1.0 - v) * ow;
        yo = u * oh;
        break;
      default:
        xo = u * ow;
        yo = v * oh;
        break;
    }

    final int xi = xo.round().clamp(0, ow - 1);
    final int yi = yo.round().clamp(0, oh - 1);
    return <int>[xi, yi];
  }

  List<double> _originalToUvN(int xo, int yo) {
    final int ow = _origW ?? (_imgW ?? 1);
    final int oh = _origH ?? (_imgH ?? 1);
    switch (_orient) {
      case 3:
        return [1.0 - (xo / ow), 1.0 - (yo / oh)];
      case 6:
        return [1.0 - (yo / oh), (xo / ow)];
      case 8:
        return [(yo / oh), 1.0 - (xo / ow)];
      default:
        return [(xo / ow), (yo / oh)];
    }
  }

  Rect? _baseImageRect(Size viewport) {
    final int? w = _imgW;
    final int? h = _imgH;
    if (w == null || h == null || viewport.width <= 0 || viewport.height <= 0) {
      return null;
    }
    final double scale = math.min(viewport.width / w, viewport.height / h);
    final double paintW = w * scale;
    final double paintH = h * scale;
    final double left = (viewport.width - paintW) / 2.0;
    final double top = (viewport.height - paintH) / 2.0;
    return Rect.fromLTWH(left, top, paintW, paintH);
  }

  Rect? _currentImageRect(Size viewport) {
    final Rect? base = _baseImageRect(viewport);
    if (base == null) return null;

    final double scale = _zoomMode ? _zoomScale : 1.0;
    final double offsetX = _zoomMode ? _zoomOffsetX : 0.0;
    final double offsetY = _zoomMode ? _zoomOffsetY : 0.0;
    final Offset center = base.center + Offset(offsetX, offsetY);
    final double width = base.width * scale;
    final double height = base.height * scale;
    return Rect.fromCenter(center: center, width: width, height: height);
  }

  void _nudgeAim(int dx, int dy) {
    if (!_aimMode) return;
    final int ow = _origW ?? (_imgW ?? 0);
    final int oh = _origH ?? (_imgH ?? 0);
    if (ow <= 0 || oh <= 0) return;
    setState(() {
      _aimX = ((_aimX ?? 0) + dx).clamp(0, ow - 1);
      _aimY = ((_aimY ?? 0) + dy).clamp(0, oh - 1);
    });
  }

  void _nudgeVisualUp() {
    switch (_orient) {
      case 1:
        _nudgeAim(0, -_nudgeStep);
        break;
      case 3:
        _nudgeAim(0, _nudgeStep);
        break;
      case 6:
        _nudgeAim(-_nudgeStep, 0);
        break;
      case 8:
        _nudgeAim(_nudgeStep, 0);
        break;
      default:
        _nudgeAim(0, -_nudgeStep);
    }
  }

  void _nudgeVisualDown() {
    switch (_orient) {
      case 1:
        _nudgeAim(0, _nudgeStep);
        break;
      case 3:
        _nudgeAim(0, -_nudgeStep);
        break;
      case 6:
        _nudgeAim(_nudgeStep, 0);
        break;
      case 8:
        _nudgeAim(-_nudgeStep, 0);
        break;
      default:
        _nudgeAim(0, _nudgeStep);
    }
  }

  void _nudgeVisualLeft() {
    switch (_orient) {
      case 1:
        _nudgeAim(-_nudgeStep, 0);
        break;
      case 3:
        _nudgeAim(_nudgeStep, 0);
        break;
      case 6:
        _nudgeAim(0, _nudgeStep);
        break;
      case 8:
        _nudgeAim(0, -_nudgeStep);
        break;
      default:
        _nudgeAim(-_nudgeStep, 0);
    }
  }

  void _nudgeVisualRight() {
    switch (_orient) {
      case 1:
        _nudgeAim(_nudgeStep, 0);
        break;
      case 3:
        _nudgeAim(-_nudgeStep, 0);
        break;
      case 6:
        _nudgeAim(0, -_nudgeStep);
        break;
      case 8:
        _nudgeAim(0, _nudgeStep);
        break;
      default:
        _nudgeAim(_nudgeStep, 0);
    }
  }

  void _beginAccurateSelection() {
    final int ow = _origW ?? (_imgW ?? 0);
    final int oh = _origH ?? (_imgH ?? 0);
    if (ow <= 0 || oh <= 0) return;
    final int cx = (_aimX ?? (ow ~/ 2)).clamp(0, ow - 1);
    final int cy = (_aimY ?? (oh ~/ 2)).clamp(0, oh - 1);
    setState(() {
      _aimX = cx;
      _aimY = cy;
      _aimMode = true;
    });
  }

  Future<void> _confirmAimAndProceed() async {
    if (!_aimMode || _aimX == null || _aimY == null) return;
    final int xPx = _aimX!;
    final int yPx = _aimY!;
    final int ow = _origW ?? (_imgW ?? 0);
    final int xTr = ow > 0 ? ((ow - 1) - xPx) : xPx;
    setState(() {
      _focuses[_index] = <int>[xTr, yPx];
      _aimMode = false;
    });
    if (_index < 3) {
      setState(() {
        _index++;
      });
      await _prepareCurrent();
    } else {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                SizedBox(height: 8),
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Generating GIF…'),
              ],
            ),
          ),
        ),
      );
      final f1 = _focuses[0] ?? [0, 0];
      final f2 = _focuses[1] ?? [0, 0];
      final f3 = _focuses[2] ?? [0, 0];
      final f4 = _focuses[3] ?? [0, 0];
      final int code = await fullFunction(
        widget.baseName,
        f1,
        f2,
        f3,
        f4,
        200,
        widget.dirPath,
      );
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      try {
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();
      } catch (_) {}
      final String newGifPath = p.join(
        widget.dirPath,
        '${widget.baseName}.gif',
      );
      final bool ok = code == 0 && File(newGifPath).existsSync();
      try {
        final provider = FileImage(File(newGifPath));
        PaintingBinding.instance.imageCache.evict(provider);
      } catch (_) {}
      if (ok) {
        Navigator.of(context).pop('updated:' + newGifPath);
      } else {
        Navigator.of(context).pop('updated:'); // no path indicates failure
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok ? 'GIF generated successfully.' : 'GIF generation failed.',
          ),
        ),
      );
    }
  }

  void _onTapUp(TapUpDetails d, Size viewport) async {
    final int? w = _imgW;
    final int? h = _imgH;
    if (w == null || h == null) return;

    final Rect? rect = _currentImageRect(viewport);
    if (rect == null) return;
    final Offset lp = d.localPosition;
    final double lx = (lp.dx - rect.left).clamp(0.0, rect.width);
    final double ly = (lp.dy - rect.top).clamp(0.0, rect.height);
    final double u = rect.width > 0 ? (lx / rect.width) : 0.0;
    final double v = rect.height > 0 ? (ly / rect.height) : 0.0;
    final int xr = (u * w).round().clamp(0, w - 1);
    final int yr = (v * h).round().clamp(0, h - 1);
    final List<int> orig = _mapRenderedToOriginal(xr, yr, w, h);
    final int xPx = orig[0];
    final int yPx = orig[1];

    if (_aimMode) {
      setState(() {
        _aimX = xPx;
        _aimY = yPx;
      });
      return;
    }

    final int ow = _origW ?? (_imgW ?? 0);
    final int xTr = ow > 0 ? ((ow - 1) - xPx) : xPx;
    setState(() {
      _focuses[_index] = <int>[xTr, yPx];
    });
    if (_index < 3) {
      setState(() {
        _index++;
      });
      _prepareCurrent();
    } else {
      final f1 = _focuses[0] ?? [0, 0];
      final f2 = _focuses[1] ?? [0, 0];
      final f3 = _focuses[2] ?? [0, 0];
      final f4 = _focuses[3] ?? [0, 0];
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                SizedBox(height: 8),
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Generating GIF…'),
              ],
            ),
          ),
        ),
      );

      final int code = await fullFunction(
        widget.baseName,
        f1,
        f2,
        f3,
        f4,
        200,
        widget.dirPath,
      );

      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      try {
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();
      } catch (_) {}
      final String newGifPath = p.join(
        widget.dirPath,
        '${widget.baseName}.gif',
      );
      try {
        final provider = FileImage(File(newGifPath));
        PaintingBinding.instance.imageCache.evict(provider);
      } catch (_) {}
      Navigator.of(context).pop('updated:' + newGifPath);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            code == 0
                ? 'GIF generated successfully.'
                : 'GIF generation failed (code $code).',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('Select focus: frame ${_index + 1} / 4'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Center(
              child: BatteryIndicator(
                textStyle: const TextStyle(color: Colors.white, fontSize: 14),
                iconColor: Colors.white,
              ),
            ),
          ),
          IconButton(
            icon: Icon(_zoomMode ? Icons.zoom_out : Icons.zoom_in),
            onPressed: () {
              setState(() {
                _zoomMode = !_zoomMode;
                if (_zoomMode) {
                  _aimMode = false;
                }
              });
            },
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          final path = _paths[_index];
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) => _onTapUp(d, size),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (_imgW == null || _imgH == null)
                  const Center(child: CircularProgressIndicator())
                else
                  Transform.translate(
                    offset: Offset(
                      _zoomMode ? _zoomOffsetX : 0,
                      _zoomMode ? _zoomOffsetY : 0,
                    ),
                    child: Transform.scale(
                      scale: _zoomMode ? _zoomScale : 1.0,
                      child: Center(
                        child: SizedBox(
                          width: size.width,
                          height: size.height,
                          child: Image.file(File(path), fit: BoxFit.contain),
                        ),
                      ),
                    ),
                  ),
                if (!_zoomMode)
                  SafeArea(
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: ElevatedButton(
                          onPressed: _beginAccurateSelection,
                          child: const Text('Accurate selection'),
                        ),
                      ),
                    ),
                  ),
                if (_zoomMode)
                  ...(() {
                    // Overlay four directional arrow buttons for zoom panning
                    const double btnSize = 64;
                    const double step = 50.0;
                    return <Widget>[
                      // Up
                      Positioned(
                        left: (size.width - btnSize) / 2,
                        top: 36,
                        child: Material(
                          color: Colors.black45,
                          shape: const StadiumBorder(),
                          child: SizedBox(
                            width: btnSize,
                            height: btnSize,
                            child: IconButton(
                              iconSize: 36,
                              tooltip: 'Move up',
                              icon: const Icon(
                                Icons.keyboard_arrow_up,
                                color: Colors.white,
                              ),
                              onPressed: () {
                                setState(() {
                                  _zoomOffsetY += step;
                                });
                              },
                            ),
                          ),
                        ),
                      ),
                      // Down
                      Positioned(
                        left: (size.width - btnSize) / 2,
                        bottom: 36,
                        child: Material(
                          color: Colors.black45,
                          shape: const StadiumBorder(),
                          child: SizedBox(
                            width: btnSize,
                            height: btnSize,
                            child: IconButton(
                              iconSize: 36,
                              tooltip: 'Move down',
                              icon: const Icon(
                                Icons.keyboard_arrow_down,
                                color: Colors.white,
                              ),
                              onPressed: () {
                                setState(() {
                                  _zoomOffsetY -= step;
                                });
                              },
                            ),
                          ),
                        ),
                      ),
                      // Left
                      Positioned(
                        left: 36,
                        top: (size.height - btnSize) / 2,
                        child: Material(
                          color: Colors.black45,
                          shape: const StadiumBorder(),
                          child: SizedBox(
                            width: btnSize,
                            height: btnSize,
                            child: IconButton(
                              iconSize: 36,
                              tooltip: 'Move left',
                              icon: const Icon(
                                Icons.keyboard_arrow_left,
                                color: Colors.white,
                              ),
                              onPressed: () {
                                setState(() {
                                  _zoomOffsetX += step;
                                });
                              },
                            ),
                          ),
                        ),
                      ),
                      // Right
                      Positioned(
                        right: 36,
                        top: (size.height - btnSize) / 2,
                        child: Material(
                          color: Colors.black45,
                          shape: const StadiumBorder(),
                          child: SizedBox(
                            width: btnSize,
                            height: btnSize,
                            child: IconButton(
                              iconSize: 36,
                              tooltip: 'Move right',
                              icon: const Icon(
                                Icons.keyboard_arrow_right,
                                color: Colors.white,
                              ),
                              onPressed: () {
                                setState(() {
                                  _zoomOffsetX -= step;
                                });
                              },
                            ),
                          ),
                        ),
                      ),
                    ];
                  }()),
                if (_aimMode &&
                    _imgW != null &&
                    _imgH != null &&
                    _aimX != null &&
                    _aimY != null)
                  ...(() {
                    final Rect? rect = _currentImageRect(size);
                    if (rect == null) return <Widget>[];
                    final List<double> uv = _originalToUvN(_aimX!, _aimY!);
                    final double rx = rect.left + uv[0] * rect.width;
                    final double ry = rect.top + uv[1] * rect.height;
                    const double cross = 18.0;
                    const double thick = 2.0;
                    const double btnSize = 64;
                    const double edgeInset = 24;
                    return <Widget>[
                      Positioned(
                        left: rx - thick / 2,
                        top: rect.top,
                        width: thick,
                        height: rect.height,
                        child: Container(color: Colors.redAccent),
                      ),
                      Positioned(
                        left: rect.left,
                        top: ry - thick / 2,
                        width: rect.width,
                        height: thick,
                        child: Container(color: Colors.redAccent),
                      ),
                      Positioned(
                        left: rx - cross / 2,
                        top: ry - cross / 2,
                        width: cross,
                        height: cross,
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: Colors.redAccent,
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(2),
                            color: Colors.black38,
                          ),
                        ),
                      ),
                      Positioned(
                        left: (size.width - btnSize) / 2,
                        top: edgeInset,
                        child: Material(
                          color: Colors.black45,
                          shape: const StadiumBorder(),
                          child: SizedBox(
                            width: btnSize,
                            height: btnSize,
                            child: IconButton(
                              iconSize: 40,
                              tooltip: 'Move up',
                              icon: const Icon(
                                Icons.keyboard_arrow_up,
                                color: Colors.white,
                              ),
                              onPressed: _nudgeVisualUp,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: (size.width - btnSize) / 2,
                        bottom: edgeInset,
                        child: Material(
                          color: Colors.black45,
                          shape: const StadiumBorder(),
                          child: SizedBox(
                            width: btnSize,
                            height: btnSize,
                            child: IconButton(
                              iconSize: 40,
                              tooltip: 'Move down',
                              icon: const Icon(
                                Icons.keyboard_arrow_down,
                                color: Colors.white,
                              ),
                              onPressed: _nudgeVisualDown,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: edgeInset,
                        top: (size.height - btnSize) / 2,
                        child: Material(
                          color: Colors.black45,
                          shape: const StadiumBorder(),
                          child: SizedBox(
                            width: btnSize,
                            height: btnSize,
                            child: IconButton(
                              iconSize: 40,
                              tooltip: 'Move left',
                              icon: const Icon(
                                Icons.keyboard_arrow_left,
                                color: Colors.white,
                              ),
                              onPressed: _nudgeVisualLeft,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        right: edgeInset,
                        top: (size.height - btnSize) / 2,
                        child: Material(
                          color: Colors.black45,
                          shape: const StadiumBorder(),
                          child: SizedBox(
                            width: btnSize,
                            height: btnSize,
                            child: IconButton(
                              iconSize: 40,
                              tooltip: 'Move right',
                              icon: const Icon(
                                Icons.keyboard_arrow_right,
                                color: Colors.white,
                              ),
                              onPressed: _nudgeVisualRight,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        right: edgeInset,
                        bottom: edgeInset,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.check_circle_outline),
                          label: const Text('Proceed'),
                          onPressed: _confirmAimAndProceed,
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(140, 44),
                          ),
                        ),
                      ),
                    ];
                  }()),
              ],
            ),
          );
        },
      ),
    );
  }
}
