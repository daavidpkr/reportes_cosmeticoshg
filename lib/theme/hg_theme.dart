import 'package:flutter/material.dart';

@immutable
class HgThemeColors extends ThemeExtension<HgThemeColors> {
  const HgThemeColors({
    required this.panel,
    required this.input,
    required this.tableHeader,
    required this.mutedText,
    required this.disabledText,
    required this.burgundy,
    required this.plum,
    required this.lilac,
    required this.gold,
    required this.positive,
    required this.positiveContainer,
    required this.warning,
    required this.warningContainer,
    required this.danger,
    required this.hover,
  });

  final Color panel;
  final Color input;
  final Color tableHeader;
  final Color mutedText;
  final Color disabledText;
  final Color burgundy;
  final Color plum;
  final Color lilac;
  final Color gold;
  final Color positive;
  final Color positiveContainer;
  final Color warning;
  final Color warningContainer;
  final Color danger;
  final Color hover;

  static const light = HgThemeColors(
    panel: Colors.white,
    input: Colors.white,
    tableHeader: Color(0xFFF5F3F6),
    mutedText: Color(0xFF8A7C89),
    disabledText: Color(0xFFAAA0A9),
    burgundy: Color(0xFF7A1F3D),
    plum: Color(0xFF3D1A4A),
    lilac: Color(0xFFC9A8D4),
    gold: Color(0xFFC9A24C),
    positive: Color(0xFF3F8158),
    positiveContainer: Color(0xFFE5F2E9),
    warning: Color(0xFFB8863B),
    warningContainer: Color(0xFFFBF0DC),
    danger: Color(0xFFA8425A),
    hover: Color(0x147A1F3D),
  );

  static const dark = HgThemeColors(
    panel: Color(0xFF251C26),
    input: Color(0xFF2D232E),
    tableHeader: Color(0xFF211922),
    mutedText: Color(0xFFBBAFBA),
    disabledText: Color(0xFF81747F),
    burgundy: Color(0xFFA84D70),
    plum: Color(0xFFC9A8D4),
    lilac: Color(0xFFC9A8D4),
    gold: Color(0xFFC9A24C),
    positive: Color(0xFF72B88A),
    positiveContainer: Color(0xFF20372A),
    warning: Color(0xFFD4AC5B),
    warningContainer: Color(0xFF3A2D1D),
    danger: Color(0xFFE17A91),
    hover: Color(0x2EA84D70),
  );

  @override
  HgThemeColors copyWith() => this;

  @override
  HgThemeColors lerp(covariant HgThemeColors? other, double t) =>
      other == null ? this : (t < .5 ? this : other);
}

extension HgThemeContext on BuildContext {
  HgThemeColors get hg => Theme.of(this).extension<HgThemeColors>()!;
}
