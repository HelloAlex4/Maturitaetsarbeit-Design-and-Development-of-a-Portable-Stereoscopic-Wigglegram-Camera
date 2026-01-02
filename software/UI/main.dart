/**
 * A majority of this code was written by AI.
 * 
 * Script Name: main.dart
 * Description: 
 *   Entry point for the Flutter application. Initializes the window manager,
 *   configures the application window (size, title bar, full screen), and
 *   launches the main app widget.
 */

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  WindowOptions windowOptions = const WindowOptions(
    size: Size(800, 600),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
    fullScreen: true,
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
    await windowManager.setFullScreen(true);
  });

  runApp(const SimpleApp());
}
