/**
 * A majority of this code was written by AI.
 * 
 * Script Name: main_settings_page.dart
 * Description: 
 *   Comprehensive settings dashboard. Allows configuration of camera parameters 
 *   (ISO, Shutter, WB), connectivity (Wi-Fi), and system preferences.
 */

import 'package:flutter/material.dart';

import 'package:camera/models/camera_enums.dart';
import 'package:camera/pages/wifi_network_page.dart';
import 'package:camera/services/wifi_service.dart';
import 'package:camera/widgets/battery_indicator.dart';

class MainSettingsPage extends StatefulWidget {
  const MainSettingsPage({super.key});
  @override
  State<MainSettingsPage> createState() => _MainSettingsPageState();
}

class _MainSettingsPageState extends State<MainSettingsPage> {
  int _selectedSection = 0;

  // Connectivity
  bool wifiEnabled = true;
  String? wifiError;

  // Camera prototypes
  ExposureMode exposureMode = ExposureMode.auto;
  ISO iso = ISO.iso100;
  ShutterSpeed shutter = ShutterSpeed.s1_125;
  WhiteBalance whiteBalance = WhiteBalance.auto;
  FocusMode focusMode = FocusMode.continuous;
  Stabilization stabilization = Stabilization.standard;
  FlashSetting flash = FlashSetting.auto;
  PhotoResolution photoResolution = PhotoResolution.mp24;
  VideoResolution videoResolution = VideoResolution.uhd4k;
  VideoFramerate videoFps = VideoFramerate.fps30;
  MeteringMode metering = MeteringMode.matrix;
  DriveMode driveMode = DriveMode.single;
  FileFormat fileFormat = FileFormat.jpeg;
  bool rawCapture = false;
  bool zebras = false;
  bool histogram = true;
  bool gridOverlay = false;
  bool aeLock = false;
  bool afAssistLamp = false;
  bool ndFilter = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Center(
              child: BatteryIndicator(
                textStyle: const TextStyle(fontSize: 14),
              ),
            ),
          ),
        ],
      ),
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _selectedSection,
            onDestinationSelected: (i) => setState(() => _selectedSection = i),
            labelType: NavigationRailLabelType.all,
            leading: const SizedBox(height: 8),
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.photo_camera_outlined),
                selectedIcon: Icon(Icons.photo_camera),
                label: Text('Camera'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.wifi),
                selectedIcon: Icon(Icons.wifi_rounded),
                label: Text('Connectivity'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.settings_suggest_outlined),
                selectedIcon: Icon(Icons.settings_suggest),
                label: Text('System'),
              ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: IndexedStack(
              index: _selectedSection,
              children: [
                _buildCameraSettings(context),
                _buildConnectivitySettings(context),
                _buildSystemSettings(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
    child: Text(
      title,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
    ),
  );

  Widget _buildConnectivitySettings(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        _sectionHeader('Wi‑Fi'),
        FutureBuilder(
          future: WifiService.getStatus(),
          builder: (context, snap) {
            final st = snap.data;
            final enabled = st?.wifiEnabled ?? wifiEnabled;
            return SwitchListTile(
              title: const Text('Enable Wi‑Fi'),
              subtitle: st?.error != null
                  ? Text(st!.error!, style: const TextStyle(color: Colors.red))
                  : null,
              value: enabled,
              onChanged: (v) async {
                final ok = await WifiService.setWifiEnabled(v);
                setState(() {
                  wifiEnabled = ok ? v : wifiEnabled;
                });
              },
            );
          },
        ),
        ListTile(
          leading: const Icon(Icons.wifi_tethering),
          title: const Text('Network…'),
          subtitle: const Text('Select SSID and enter password'),
          onTap: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const WifiNetworkPage())),
        ),
      ],
    );
  }

  Widget _buildSystemSettings(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        _sectionHeader('System'),
        ListTile(
          leading: const Icon(Icons.info_outline),
          title: const Text('About device'),
          subtitle: const Text('Model, firmware, storage'),
          onTap: () {},
        ),
        ListTile(
          leading: const Icon(Icons.restart_alt),
          title: const Text('Restart'),
          onTap: () {},
        ),
      ],
    );
  }

  Widget _buildCameraSettings(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        _sectionHeader('Capture'),
        _enumTile<ExposureMode>(
          title: 'Exposure mode',
          value: exposureMode,
          values: ExposureMode.values,
          labelBuilder: (v) => _label(v.name),
          onChanged: (v) => setState(() => exposureMode = v!),
        ),
        if (exposureMode == ExposureMode.manual) ...[
          _enumTile<ISO>(
            title: 'ISO',
            value: iso,
            values: ISO.values,
            labelBuilder: (v) => v.label,
            onChanged: (v) => setState(() => iso = v!),
          ),
          _enumTile<ShutterSpeed>(
            title: 'Shutter',
            value: shutter,
            values: ShutterSpeed.values,
            labelBuilder: (v) => v.label,
            onChanged: (v) => setState(() => shutter = v!),
          ),
        ],
        _enumTile<WhiteBalance>(
          title: 'White balance',
          value: whiteBalance,
          values: WhiteBalance.values,
          labelBuilder: (v) => _label(v.name),
          onChanged: (v) => setState(() => whiteBalance = v!),
        ),
        _enumTile<FocusMode>(
          title: 'Focus mode',
          value: focusMode,
          values: FocusMode.values,
          labelBuilder: (v) => _label(v.name),
          onChanged: (v) => setState(() => focusMode = v!),
        ),
        _enumTile<Stabilization>(
          title: 'Stabilization',
          value: stabilization,
          values: Stabilization.values,
          labelBuilder: (v) => _label(v.name),
          onChanged: (v) => setState(() => stabilization = v!),
        ),
        _enumTile<FlashSetting>(
          title: 'Flash',
          value: flash,
          values: FlashSetting.values,
          labelBuilder: (v) => _label(v.name),
          onChanged: (v) => setState(() => flash = v!),
        ),

        _sectionHeader('Photo'),
        _enumTile<PhotoResolution>(
          title: 'Resolution',
          value: photoResolution,
          values: PhotoResolution.values,
          labelBuilder: (v) => v.label,
          onChanged: (v) => setState(() => photoResolution = v!),
        ),
        _enumTile<FileFormat>(
          title: 'File format',
          value: fileFormat,
          values: FileFormat.values,
          labelBuilder: (v) => _label(v.name),
          onChanged: (v) => setState(() => fileFormat = v!),
        ),
        SwitchListTile(
          title: const Text('Capture RAW'),
          value: rawCapture,
          onChanged: (v) => setState(() => rawCapture = v),
        ),

        _sectionHeader('Video'),
        _enumTile<VideoResolution>(
          title: 'Resolution',
          value: videoResolution,
          values: VideoResolution.values,
          labelBuilder: (v) => v.label,
          onChanged: (v) => setState(() => videoResolution = v!),
        ),
        _enumTile<VideoFramerate>(
          title: 'Frame rate',
          value: videoFps,
          values: VideoFramerate.values,
          labelBuilder: (v) => v.label,
          onChanged: (v) => setState(() => videoFps = v!),
        ),

        _sectionHeader('Metering & Drive'),
        _enumTile<MeteringMode>(
          title: 'Metering mode',
          value: metering,
          values: MeteringMode.values,
          labelBuilder: (v) => _label(v.name),
          onChanged: (v) => setState(() => metering = v!),
        ),
        _enumTile<DriveMode>(
          title: 'Drive mode',
          value: driveMode,
          values: DriveMode.values,
          labelBuilder: (v) => _label(v.name),
          onChanged: (v) => setState(() => driveMode = v!),
        ),

        _sectionHeader('Overlays'),
        SwitchListTile(
          title: const Text('Zebra stripes'),
          value: zebras,
          onChanged: (v) => setState(() => zebras = v),
        ),
        SwitchListTile(
          title: const Text('Histogram'),
          value: histogram,
          onChanged: (v) => setState(() => histogram = v),
        ),
        SwitchListTile(
          title: const Text('Grid overlay'),
          value: gridOverlay,
          onChanged: (v) => setState(() => gridOverlay = v),
        ),

        _sectionHeader('Assists'),
        SwitchListTile(
          title: const Text('AE lock'),
          value: aeLock,
          onChanged: (v) => setState(() => aeLock = v),
        ),
        SwitchListTile(
          title: const Text('AF assist lamp'),
          value: afAssistLamp,
          onChanged: (v) => setState(() => afAssistLamp = v),
        ),
        SwitchListTile(
          title: const Text('ND filter'),
          value: ndFilter,
          onChanged: (v) => setState(() => ndFilter = v),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  String _label(String snakeOrCamel) {
    // Convert simple enum names to Title Case labels
    return snakeOrCamel
        .replaceAll('_', ' ')
        .replaceAllMapped(RegExp(r'(^|\s)[a-z]'), (m) => m[0]!.toUpperCase());
  }

  Widget _enumTile<T>({
    required String title,
    required T value,
    required List<T> values,
    required String Function(T v) labelBuilder,
    required ValueChanged<T?> onChanged,
  }) {
    return ListTile(
      title: Text(title),
      trailing: DropdownButton<T>(
        value: value,
        items: values
            .map(
              (v) =>
                  DropdownMenuItem<T>(value: v, child: Text(labelBuilder(v))),
            )
            .toList(),
        onChanged: onChanged,
      ),
    );
  }
}
