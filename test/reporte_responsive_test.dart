import 'package:cosmeticos_hg_reportes/screens/reporte_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('geometría responsive compartida de reportes', () {
    test('selecciona las tres densidades con tipografía propia', () {
      expect(
          ReportResponsiveLayout.forWidth(1024).density, ReportDensity.compact);
      expect(ReportResponsiveLayout.forWidth(1280).tableFontSize, 12.5);
      expect(
          ReportResponsiveLayout.forWidth(1366).density, ReportDensity.normal);
      expect(ReportResponsiveLayout.forWidth(1366).tableFontSize, 13.5);
      expect(ReportResponsiveLayout.forWidth(1600).density, ReportDensity.wide);
      expect(ReportResponsiveLayout.forWidth(1920).tableFontSize, 15);
    });

    test('la tabla ocupa el ancho útil y limita el scroll a 1024', () {
      for (final width in [1280.0, 1366.0, 1600.0, 1920.0]) {
        final layout = ReportResponsiveLayout.forWidth(width);
        expect(layout.table.tableWidth, layout.contentWidth);
        expect(layout.table.needsHorizontalScroll, isFalse);
      }
      final narrow = ReportResponsiveLayout.forWidth(1024);
      expect(narrow.table.tableWidth, 1180);
      expect(narrow.table.needsHorizontalScroll, isTrue);
    });

    test('el sobrante amplio prioriza cliente, nombre y vendedor', () {
      final at1600 = ReportResponsiveLayout.forWidth(1600).table;
      final at1920 = ReportResponsiveLayout.forWidth(1920).table;
      expect(at1920.clientWidth, greaterThan(at1600.clientWidth));
      expect(at1920.businessNameWidth, greaterThan(at1600.businessNameWidth));
      expect(at1920.sellerWidth, greaterThan(at1600.sellerWidth));
      expect(at1920.clientWidth, greaterThan(at1920.sellerWidth));
      expect(at1920.businessNameWidth, greaterThan(at1920.sellerWidth));
    });

    test('la tabla distingue interacción sin duplicar geometría', () {
      expect(ReportTableMode.values,
          [ReportTableMode.editable, ReportTableMode.readOnly]);
    });
  });

  group('rectángulos del marco real', () {
    for (final size in const [
      Size(1024, 768),
      Size(1280, 720),
      Size(1366, 768),
      Size(1600, 900),
      Size(1920, 1080),
    ]) {
      testWidgets('${size.width.toInt()}×${size.height.toInt()} alinea bloques',
          (tester) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final layout = ReportResponsiveLayout.forWidth(size.width);

        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: ReportDesktopFrame(
              layout: layout,
              header: const SizedBox(height: 48),
              kpis: const _MeasuredBlock(
                key: ValueKey('kpis'),
                height: 76,
              ),
              toolbar: const _MeasuredBlock(
                key: ValueKey('toolbar'),
                height: 58,
              ),
              table: const _MeasuredBlock(
                key: ValueKey('table'),
                height: 200,
              ),
            ),
          ),
        ));

        final kpis = tester.getRect(find.byKey(const ValueKey('kpis')));
        final toolbar = tester.getRect(find.byKey(const ValueKey('toolbar')));
        final table = tester.getRect(find.byKey(const ValueKey('table')));

        for (final rect in [kpis, toolbar, table]) {
          expect(rect.left, closeTo(layout.pagePadding, .01));
          expect(
            rect.right,
            closeTo(size.width - layout.pagePadding, .01),
          );
          expect(rect.width, closeTo(layout.contentWidth, .01));
        }
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('alineación interna editable y solo lectura', () {
    for (final size in const [
      Size(1024, 768),
      Size(1280, 720),
      Size(1366, 768),
      Size(1600, 900),
      Size(1920, 1080),
    ]) {
      testWidgets(
          '${size.width.toInt()}×${size.height.toInt()} no deja franja antes de NRO',
          (tester) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final layout = ReportResponsiveLayout.forWidth(size.width);
        final editableController = ScrollController();
        final readOnlyController = ScrollController();
        addTearDown(editableController.dispose);
        addTearDown(readOnlyController.dispose);

        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: EdgeInsets.symmetric(horizontal: layout.pagePadding),
              child: Column(
                children: [
                  Expanded(
                    child: _TableGeometryProbe(
                      prefix: 'editable',
                      minimumWidth: layout.table.tableWidth,
                      controller: editableController,
                      editable: true,
                    ),
                  ),
                  Expanded(
                    child: _TableGeometryProbe(
                      prefix: 'readonly',
                      minimumWidth: layout.table.tableWidth,
                      controller: readOnlyController,
                      editable: false,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ));

        double leadingInset(String prefix) {
          final surface = tester.getRect(
            find.byKey(ValueKey('$prefix-surface')),
          );
          final nro = tester.getRect(find.byKey(ValueKey('$prefix-nro')));
          return nro.left - surface.left;
        }

        double trailingInset(String prefix) {
          final surface = tester.getRect(
            find.byKey(ValueKey('$prefix-surface')),
          );
          final saldo = tester.getRect(find.byKey(ValueKey('$prefix-saldo')));
          return surface.right - saldo.right;
        }

        final editableInset = leadingInset('editable');
        final readOnlyInset = leadingInset('readonly');
        expect(editableInset, lessThanOrEqualTo(32));
        expect(readOnlyInset, lessThanOrEqualTo(32));
        expect((editableInset - readOnlyInset).abs(), lessThanOrEqualTo(8));
        expect(trailingInset('editable'), lessThanOrEqualTo(32));
        expect(trailingInset('readonly'), lessThanOrEqualTo(32));
        expect(editableController.offset, 0);
        expect(readOnlyController.offset, 0);
        expect(tester.takeException(), isNull);
      });
    }
  });
}

class _MeasuredBlock extends StatelessWidget {
  const _MeasuredBlock({required super.key, required this.height});

  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        height: height,
      );
}

class _TableGeometryProbe extends StatelessWidget {
  const _TableGeometryProbe({
    required this.prefix,
    required this.minimumWidth,
    required this.controller,
    required this.editable,
  });

  final String prefix;
  final double minimumWidth;
  final ScrollController controller;
  final bool editable;

  @override
  Widget build(BuildContext context) => Container(
        key: ValueKey('$prefix-viewport'),
        child: ReportTableContentFrame(
          minimumWidth: minimumWidth,
          horizontalController: controller,
          footer: editable ? const SizedBox(width: 120, height: 32) : null,
          table: SizedBox(
            key: ValueKey('$prefix-surface'),
            width: minimumWidth - 180,
            height: 100,
            child: Stack(
              children: [
                Positioned(
                  left: 7,
                  child: Text('NRO', key: ValueKey('$prefix-nro')),
                ),
                Positioned(
                  right: 7,
                  child: Text('SALDO', key: ValueKey('$prefix-saldo')),
                ),
              ],
            ),
          ),
        ),
      );
}
