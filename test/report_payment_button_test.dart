import 'package:cosmeticos_hg_reportes/models/fila_venta.dart';
import 'package:cosmeticos_hg_reportes/screens/reporte/report_invoice_table.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget app({required VoidCallback? onAdd, required VoidCallback? onValue}) =>
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ReportPaymentButton(
                payment: Abono(),
                tooltip: 'Añadir abono',
                onPressed: onAdd,
                fontSize: 14,
                buttonKey: const ValueKey('abono-1'),
              ),
              ReportPaymentButton(
                payment: Abono(valor: 27.67),
                tooltip: 'Editar abono',
                onPressed: onValue,
                fontSize: 14,
                buttonKey: const ValueKey('abono-2'),
              ),
            ],
          ),
        ),
      ),
    );

void main() {
  testWidgets('ABONO 1 and ABONO 2 share an accessible interaction area',
      (tester) async {
    var addTaps = 0;
    var valueTaps = 0;
    await tester.pumpWidget(app(
      onAdd: () => addTaps++,
      onValue: () => valueTaps++,
    ));

    final first = find.byKey(const ValueKey('abono-1'));
    final second = find.byKey(const ValueKey('abono-2'));
    expect(tester.getSize(first), tester.getSize(second));
    expect(tester.getSize(first).width, ReportPaymentButton.width);
    expect(tester.getSize(first).height, ReportPaymentButton.touchHeight);

    final firstRect = tester.getRect(first);
    await tester.tapAt(firstRect.topLeft + const Offset(2, 2));
    final secondRect = tester.getRect(second);
    await tester.tapAt(secondRect.bottomRight - const Offset(2, 2));
    expect(addTaps, 1);
    expect(valueTaps, 1);
  });

  testWidgets('active and disabled controls preserve size and mouse cursors',
      (tester) async {
    await tester.pumpWidget(app(onAdd: () {}, onValue: null));
    final active = tester.widget<OutlinedButton>(
      find.byKey(const ValueKey('abono-1')),
    );
    final disabled = tester.widget<OutlinedButton>(
      find.byKey(const ValueKey('abono-2')),
    );

    expect(active.onPressed, isNotNull);
    expect(disabled.onPressed, isNull);
    expect(
      active.style!.mouseCursor!.resolve(const {}),
      SystemMouseCursors.click,
    );
    expect(
      disabled.style!.mouseCursor!.resolve(const {WidgetState.disabled}),
      SystemMouseCursors.basic,
    );
    expect(tester.getSize(find.byKey(const ValueKey('abono-1'))),
        tester.getSize(find.byKey(const ValueKey('abono-2'))));
  });

  testWidgets('visual button remains 40 high inside a 48 high touch target',
      (tester) async {
    await tester.pumpWidget(app(onAdd: () {}, onValue: () {}));
    final button = tester.widget<OutlinedButton>(
      find.byKey(const ValueKey('abono-1')),
    );
    final minimum = button.style!.minimumSize!.resolve(const {});
    final padding = button.style!.padding!.resolve(const {});
    expect(minimum, const Size(104, 40));
    expect(padding, const EdgeInsets.symmetric(horizontal: 12, vertical: 10));
  });
}
