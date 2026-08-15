import 'dart:math' as math;

import 'package:flutter/material.dart';

enum ReportDensity { compact, normal, wide }

@immutable
class ReportResponsiveLayout {
  const ReportResponsiveLayout._({
    required this.viewportWidth,
    required this.density,
    required this.pagePadding,
    required this.sectionGap,
    required this.tableScale,
    required this.tableFontSize,
    required this.tableHeadingFontSize,
  });

  static const compactBreakpoint = 1366.0;
  static const wideBreakpoint = 1600.0;

  factory ReportResponsiveLayout.forWidth(double width) {
    if (width >= wideBreakpoint) {
      return ReportResponsiveLayout._(
        viewportWidth: width,
        density: ReportDensity.wide,
        pagePadding: 32,
        sectionGap: 18,
        tableScale: 1,
        tableFontSize: 15,
        tableHeadingFontSize: 11,
      );
    }
    if (width >= compactBreakpoint) {
      return ReportResponsiveLayout._(
        viewportWidth: width,
        density: ReportDensity.normal,
        pagePadding: 24,
        sectionGap: 14,
        tableScale: .9,
        tableFontSize: 13.5,
        tableHeadingFontSize: 10.5,
      );
    }
    return ReportResponsiveLayout._(
      viewportWidth: width,
      density: ReportDensity.compact,
      pagePadding: 16,
      sectionGap: 10,
      tableScale: .78,
      tableFontSize: 12.5,
      tableHeadingFontSize: 10,
    );
  }

  final double viewportWidth;
  final ReportDensity density;
  final double pagePadding;
  final double sectionGap;
  final double tableScale;
  final double tableFontSize;
  final double tableHeadingFontSize;

  bool get compact => density == ReportDensity.compact;
  double get contentWidth => math.max(0, viewportWidth - pagePadding * 2);

  ReportTableGeometry get table => ReportTableGeometry.forLayout(this);
}

@immutable
class ReportTableGeometry {
  const ReportTableGeometry({
    required this.availableWidth,
    required this.minimumReadableWidth,
    required this.clientWidth,
    required this.businessNameWidth,
    required this.sellerWidth,
  });

  factory ReportTableGeometry.forLayout(ReportResponsiveLayout layout) {
    final scale = layout.tableScale;
    // DataTable también distribuye espacio entre columnas no numéricas. Se
    // asigna explícitamente solo el 60 % del excedente para reservar el resto
    // a separaciones, encabezados y a esa distribución intrínseca.
    final wideSurplus = layout.density == ReportDensity.wide
        ? math.max(0, layout.contentWidth - 1460) * .6
        : 0.0;
    return ReportTableGeometry(
      availableWidth: layout.contentWidth,
      minimumReadableWidth: layout.compact ? 1180 : 1280,
      clientWidth: 220 * scale + wideSurplus * .42,
      businessNameWidth: 205 * scale + wideSurplus * .36,
      sellerWidth: 115 * scale + wideSurplus * .22,
    );
  }

  final double availableWidth;
  final double minimumReadableWidth;
  final double clientWidth;
  final double businessNameWidth;
  final double sellerWidth;

  double get tableWidth => math.max(minimumReadableWidth, availableWidth);
  bool get needsHorizontalScroll => minimumReadableWidth > availableWidth;
}

enum ReportTableMode { editable, readOnly }

class ReportDesktopFrame extends StatelessWidget {
  const ReportDesktopFrame({
    required this.layout,
    required this.header,
    required this.kpis,
    required this.toolbar,
    required this.table,
    super.key,
  });

  final ReportResponsiveLayout layout;
  final Widget header;
  final Widget kpis;
  final Widget toolbar;
  final Widget table;

  @override
  Widget build(BuildContext context) => Padding(
        key: const ValueKey('report-content-frame'),
        padding: EdgeInsets.fromLTRB(
          layout.pagePadding,
          layout.compact ? 10 : 18,
          layout.pagePadding,
          layout.compact ? 12 : 22,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            SizedBox(height: layout.sectionGap),
            kpis,
            SizedBox(height: layout.sectionGap),
            toolbar,
            SizedBox(height: layout.compact ? 8 : 12),
            Expanded(child: table),
          ],
        ),
      );
}
