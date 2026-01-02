/**
 * A majority of this code was written by AI.
 * 
 * Script Name: battery_indicator.dart
 * Description: 
 *   A reactive widget that displays the current battery percentage and 
 *   an icon that changes based on charge levels.
 */

import 'dart:async';

import 'package:flutter/material.dart';

import '../services/battery_service.dart';

class BatteryIndicator extends StatefulWidget {
  const BatteryIndicator({
    super.key,
    this.iconSize = 20,
    this.refreshInterval = const Duration(seconds: 5),
    this.textStyle,
    this.iconColor,
    this.textColor,
    this.lowBatteryWarningPercent = 15,
    this.lowBatteryColor,
    this.showPlaceholderWhenUnknown = true,
  });

  final double iconSize;
  final Duration refreshInterval;
  final TextStyle? textStyle;
  final Color? iconColor;
  final Color? textColor;
  final double lowBatteryWarningPercent;
  final Color? lowBatteryColor;
  final bool showPlaceholderWhenUnknown;

  @override
  State<BatteryIndicator> createState() => _BatteryIndicatorState();
}

class _BatteryIndicatorState extends State<BatteryIndicator> {
  double? _percent;
  Timer? _timer;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
    _timer = Timer.periodic(widget.refreshInterval, (_) {
      unawaited(_refresh());
    });
  }

  @override
  void didUpdateWidget(covariant BatteryIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshInterval != widget.refreshInterval) {
      _timer?.cancel();
      _timer = Timer.periodic(widget.refreshInterval, (_) {
        unawaited(_refresh());
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_loading) return;
    _loading = true;
    final value = await BatteryService.readBatteryPercent();
    if (!mounted) {
      _loading = false;
      return;
    }
    setState(() {
      _percent = value;
    });
    _loading = false;
  }

  @override
  Widget build(BuildContext context) {
    final percent = _percent;
    final icon = _iconForPercent(percent);
    final color = _colorForPercent(context, percent);

    final defaultTextStyle = DefaultTextStyle.of(context).style;
    final textStyle = (widget.textStyle ?? defaultTextStyle).copyWith(
      color: widget.textColor ?? color,
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(
          icon,
          size: widget.iconSize,
          color: widget.iconColor ?? color,
        ),
        if (percent != null || widget.showPlaceholderWhenUnknown)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              percent != null
                  ? '${percent.toStringAsFixed(0)}%'
                  : '--%',
              style: textStyle,
            ),
          ),
      ],
    );
  }

  IconData _iconForPercent(double? percent) {
    if (percent == null) return Icons.battery_unknown;
    if (percent <= 5) return Icons.battery_alert;
    if (percent <= 15) return Icons.battery_0_bar;
    if (percent <= 30) return Icons.battery_2_bar;
    if (percent <= 55) return Icons.battery_4_bar;
    if (percent <= 80) return Icons.battery_6_bar;
    if (percent <= 95) return Icons.battery_full;
    return Icons.battery_full;
  }

  Color _colorForPercent(BuildContext context, double? percent) {
    final base = widget.textColor ??
        widget.iconColor ??
        DefaultTextStyle.of(context).style.color ??
        IconTheme.of(context).color ??
        Colors.white;
    if (percent != null && percent <= widget.lowBatteryWarningPercent) {
      return widget.lowBatteryColor ?? Colors.redAccent;
    }
    return base;
  }
}
