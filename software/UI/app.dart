/**
 * A majority of this code was written by AI.
 * 
 * Script Name: app.dart
 * Description: 
 *   Core application widget defining the Material app structure, 
 *   custom scroll behavior for cross-platform support, and the initial route.
 */

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

import 'pages/capture_page.dart';

class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const <PointerDeviceKind>{
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
    PointerDeviceKind.unknown,
  };
}

class SimpleApp extends StatelessWidget {
  const SimpleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Camera',
      theme: ThemeData(useMaterial3: true),
      scrollBehavior: const AppScrollBehavior(),
      home: const CapturePage(),
    );
  }
}
