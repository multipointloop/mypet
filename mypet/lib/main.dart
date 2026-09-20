import 'dart:io';

import 'package:flutter/material.dart';

import 'features/pet/pet_widget.dart';
import 'features/settings/settings_page.dart';
import 'platform/win/window_service.dart';

enum PetMode { windows, androidMain, androidOverlay }

/// Entry points:
///  * Windows main engine -> transparent always-on-top pet window
///    (settings open as an adaptive panel INSIDE it)
///  * Android main activity -> settings / permission page
///  * Android overlay engine -> `overlayMain`
Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isAndroid) {
    if (args.contains('overlay')) {
      runApp(const PetApp(mode: PetMode.androidOverlay));
    } else {
      runApp(const PetApp(mode: PetMode.androidMain));
    }
    return;
  }

  await WindowsWindowService.instance.boot();
  runApp(const PetApp(mode: PetMode.windows));
}

/// overlay engine entry point used by flutter_overlay_window
@pragma("vm:entry-point")
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PetApp(mode: PetMode.androidOverlay));
}

class PetApp extends StatelessWidget {
  const PetApp({super.key, required this.mode});

  final PetMode mode;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MyPet',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'Microsoft YaHei UI',
        fontFamilyFallback: ['Microsoft YaHei', 'SimHei', 'PingFang SC'],
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFF8AB5),
          brightness: Brightness.light,
        ),
      ),
      home: switch (mode) {
        PetMode.windows => const WindowsPetHome(),
        PetMode.androidMain => const SettingsPage(),
        PetMode.androidOverlay => const AndroidOverlayPet(),
      },
    );
  }
}
