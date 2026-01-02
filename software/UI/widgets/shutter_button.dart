/**
 * A majority of this code was written by AI.
 * 
 * Script Name: shutter_button.dart
 * Description: 
 *   A custom circular UI button designed to trigger the camera capture process.
 */

import 'package:flutter/material.dart';

class ShutterButton extends StatelessWidget {
  final VoidCallback onPressed;
  const ShutterButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 105,
        height: 105,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 4),
          color: Colors.white.withOpacity(0.1),
        ),
        child: Container(
          margin: const EdgeInsets.all(8),
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
