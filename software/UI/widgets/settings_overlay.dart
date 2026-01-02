/**
 * A majority of this code was written by AI.
 * 
 * Script Name: settings_overlay.dart
 * Description: 
 *   An animated overlay providing quick access to common settings like 
 *   flash control, LED effects, and exposure.
 */

import 'package:flutter/material.dart';

import '../models/camera_enums.dart';

class SettingsOverlay extends StatelessWidget {
  final bool open;
  final FlashSetting flash;
  final ValueChanged<FlashSetting> onFlashChanged;
  final VoidCallback onOpenLed;
  final VoidCallback onOpenExposure;

  const SettingsOverlay({
    super.key,
    required this.open,
    required this.flash,
    required this.onFlashChanged,
    required this.onOpenLed,
    required this.onOpenExposure,
  });

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top + 48;
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      right: open ? 8 : -280,
      top: top,
      width: 260,
      child: IgnorePointer(
        ignoring: !open,
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(12),
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    'Settings',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
                const Divider(height: 16),
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text('Flash'),
                ),
                _flashTile(FlashSetting.off, 'Off'),
                _flashTile(FlashSetting.on, 'On'),
                const Divider(height: 20),
                ListTile(
                  leading: const Icon(Icons.bolt_outlined),
                  title: const Text('LED effects…'),
                  subtitle: const Text('Open LED control screen'),
                  dense: true,
                  onTap: () => onOpenLed(),
                ),
                ListTile(
                  leading: const Icon(Icons.exposure_outlined),
                  title: const Text('Exposure Control'),
                  subtitle: const Text('Adjust camera exposure'),
                  dense: true,
                  onTap: () => onOpenExposure(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _flashTile(FlashSetting value, String label) {
    return RadioListTile<FlashSetting>(
      value: value,
      groupValue: flash,
      onChanged: (v) => onFlashChanged(v ?? flash),
      title: Text(label),
      dense: true,
      contentPadding: EdgeInsets.zero,
    );
  }
}
