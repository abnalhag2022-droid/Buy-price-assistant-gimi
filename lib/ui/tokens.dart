import 'package:flutter/material.dart';

/// Brand colours taken from the launcher icon (navy receipt, gold coin).
abstract final class BrandColors {
  static const Color navy = Color(0xFF18365F);
  static const Color navyLight = Color(0xFF2A5490);
  static const Color gold = Color(0xFFF6C453);
  static const Color goldDark = Color(0xFF8A6400);
}

/// Spacing scale (logical pixels). Use these instead of ad-hoc numbers.
abstract final class Space {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;

  /// Side padding of every screen.
  static const EdgeInsets screen = EdgeInsets.symmetric(horizontal: lg);
}

abstract final class Radii {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const BorderRadius card = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius tile = BorderRadius.all(Radius.circular(md));
  static const BorderRadius chip = BorderRadius.all(Radius.circular(sm));
}

abstract final class Sizes {
  /// Minimum touch target (Material and Android accessibility guidance).
  static const double touchTarget = 48;
  static const double iconSm = 16;
  static const double iconMd = 20;
  static const double iconLg = 24;

  /// Content is centred and capped on tablets and landscape phones.
  static const double maxContentWidth = 720;
}

abstract final class AppDurations {
  static const Duration searchDebounce = Duration(milliseconds: 300);
  static const Duration short = Duration(milliseconds: 150);
}
