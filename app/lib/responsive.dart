// Tiny responsive helper: one breakpoint (phone vs tablet) by the shortest side.
// Keeps the layout code readable without a full design-system grid (YAGNI).

import 'package:flutter/widgets.dart';

extension ResponsiveContext on BuildContext {
  /// A tablet (iPad) if the shortest screen side is >= 600 logical px.
  bool get isTablet => MediaQuery.sizeOf(this).shortestSide >= 600;
}
