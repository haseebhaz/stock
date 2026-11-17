import 'package:flutter/services.dart';

/// Short sound + vibration so staff can scan without looking at the screen.
/// Android's built-in sounds are limited, so the two cases differ mainly by vibration:
/// found = one short pulse, not found = two strong pulses.
class ScanFeedback {
  static Future<void> found(bool enabled) async {
    if (!enabled) return;
    SystemSound.play(SystemSoundType.click);
    await HapticFeedback.mediumImpact();
  }

  static Future<void> notFound(bool enabled) async {
    if (!enabled) return;
    SystemSound.play(SystemSoundType.alert);
    await HapticFeedback.vibrate();
    await Future<void>.delayed(const Duration(milliseconds: 180));
    await HapticFeedback.vibrate();
  }
}
