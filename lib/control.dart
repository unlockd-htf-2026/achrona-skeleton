// Control for the Phase 1 Android investigation: plain Flutter, zero fscene.
// If this also fails to draw on the emulator, the emulator is the problem.
import 'package:flutter/material.dart';

void main() => runApp(const MaterialApp(
      home: Scaffold(
        backgroundColor: Color(0xFF104D2A),
        body: Center(
          child: Text('PLAIN FLUTTER OK',
              style: TextStyle(color: Colors.white, fontSize: 32)),
        ),
      ),
    ));
