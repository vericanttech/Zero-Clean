// ─────────────────────────────────────────────
//  ZERO-CLEAN  ·  Device info helper
// ─────────────────────────────────────────────

import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';

/// Returns the device/model name used to capture (e.g. "Pixel 6", "iPhone14,2").
/// Useful for dataset metadata so you can stratify or analyze by capture device later.
Future<String?> getDeviceModel() async {
  try {
    final plugin = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final android = await plugin.androidInfo;
      return android.model;
    }
    if (Platform.isIOS) {
      final ios = await plugin.iosInfo;
      return ios.model;
    }
  } catch (_) {}
  return null;
}
