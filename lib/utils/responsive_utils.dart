import 'package:flutter/material.dart';

/// Screen type categorization for responsive layouts
enum ScreenType {
  compact,   // Phones (< 600 width)
  medium,    // Tablets in portrait / split view (600 <= width < 900)
  expanded,  // Tablets in landscape / Desktops (>= 900 width)
}

/// Helper methods and extensions for responsive design
class ResponsiveUtils {
  static const double compactBreakpoint = 600.0;
  static const double mediumBreakpoint = 900.0;

  static ScreenType getScreenType(double width) {
    if (width < compactBreakpoint) return ScreenType.compact;
    if (width < mediumBreakpoint) return ScreenType.medium;
    return ScreenType.expanded;
  }

  static bool useWideLayout(double width, double height, Orientation orientation) {
    // True on tablets / desktops (width >= 600), or phones held sideways in landscape (height < 500)
    return width >= compactBreakpoint || (orientation == Orientation.landscape && height < 500);
  }

  static bool isPhoneLandscape(double height, Orientation orientation) {
    return orientation == Orientation.landscape && height < 500;
  }

  /// Displays an adaptive modal:
  /// - On compact screens: BottomSheet sliding up from the bottom
  /// - On medium/expanded screens: Centered dialog with max-width constraint
  static Future<T?> showAdaptiveModal<T>({
    required BuildContext context,
    required Widget child,
    double maxWidth = 560.0,
    bool isScrollControlled = true,
  }) {
    final width = MediaQuery.of(context).size.width;
    final isCompact = width < compactBreakpoint;

    if (isCompact) {
      return showModalBottomSheet<T>(
        context: context,
        isScrollControlled: isScrollControlled,
        backgroundColor: Colors.transparent,
        builder: (context) => child,
      );
    } else {
      return showDialog<T>(
        context: context,
        builder: (context) => Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: child,
              ),
            ),
          ),
        ),
      );
    }
  }
}

/// Extension on BuildContext for quick access to responsive properties
extension ResponsiveContextExtension on BuildContext {
  Size get screenSize => MediaQuery.of(this).size;
  Orientation get screenOrientation => MediaQuery.of(this).orientation;

  ScreenType get screenType => ResponsiveUtils.getScreenType(screenSize.width);

  bool get isCompact => screenSize.width < ResponsiveUtils.compactBreakpoint;
  bool get isMedium => screenSize.width >= ResponsiveUtils.compactBreakpoint && screenSize.width < ResponsiveUtils.mediumBreakpoint;
  bool get isExpanded => screenSize.width >= ResponsiveUtils.mediumBreakpoint;

  /// Returns true for iPad landscape/portrait, desktop, and compact phone-landscape mode
  bool get useWideLayout => ResponsiveUtils.useWideLayout(screenSize.width, screenSize.height, screenOrientation);

  /// Returns true specifically for phones held sideways in landscape
  bool get isPhoneLandscape => ResponsiveUtils.isPhoneLandscape(screenSize.height, screenOrientation);
}
