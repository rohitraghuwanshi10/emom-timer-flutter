import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:emom_timer_flutter/utils/responsive_utils.dart';

void main() {
  group('ResponsiveUtils Breakpoints', () {
    test('Correctly identifies compact devices (phones)', () {
      expect(ResponsiveUtils.getScreenType(375), ScreenType.compact); // iPhone SE
      expect(ResponsiveUtils.getScreenType(430), ScreenType.compact); // iPhone 15 Pro Max
      expect(ResponsiveUtils.getScreenType(599), ScreenType.compact);
    });

    test('Correctly identifies medium devices (iPad portrait / split-view)', () {
      expect(ResponsiveUtils.getScreenType(600), ScreenType.medium);
      expect(ResponsiveUtils.getScreenType(768), ScreenType.medium); // iPad Mini portrait
      expect(ResponsiveUtils.getScreenType(834), ScreenType.medium); // iPad Pro 11 portrait
      expect(ResponsiveUtils.getScreenType(899), ScreenType.medium);
    });

    test('Correctly identifies expanded devices (iPad landscape / desktop)', () {
      expect(ResponsiveUtils.getScreenType(900), ScreenType.expanded);
      expect(ResponsiveUtils.getScreenType(1024), ScreenType.expanded); // iPad Landscape
      expect(ResponsiveUtils.getScreenType(1280), ScreenType.expanded); // Desktop
      expect(ResponsiveUtils.getScreenType(1920), ScreenType.expanded); // 1080p Monitor
    });

    test('useWideLayout is true for tablet and desktop dimensions', () {
      // iPad portrait
      expect(ResponsiveUtils.useWideLayout(768, 1024, Orientation.portrait), isTrue);
      // iPad landscape
      expect(ResponsiveUtils.useWideLayout(1024, 768, Orientation.landscape), isTrue);
      // macOS desktop
      expect(ResponsiveUtils.useWideLayout(1200, 800, Orientation.landscape), isTrue);
    });

    test('useWideLayout is true for phone landscape mode', () {
      // iPhone in landscape (e.g. 844 x 390)
      expect(ResponsiveUtils.useWideLayout(844, 390, Orientation.landscape), isTrue);
    });

    test('useWideLayout is false for phone portrait mode', () {
      // iPhone in portrait (e.g. 390 x 844)
      expect(ResponsiveUtils.useWideLayout(390, 844, Orientation.portrait), isFalse);
    });

    test('isPhoneLandscape identifies compact phone landscape', () {
      expect(ResponsiveUtils.isPhoneLandscape(390, Orientation.landscape), isTrue);
      expect(ResponsiveUtils.isPhoneLandscape(768, Orientation.landscape), isFalse); // iPad
      expect(ResponsiveUtils.isPhoneLandscape(390, Orientation.portrait), isFalse);
    });
  });
}
