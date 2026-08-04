import 'package:cosmeticos_hg_reportes/app.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('muestra la pantalla principal del reporte', (tester) async {
    await tester.pumpWidget(const CosmeticosHGApp());

    expect(find.text('COSMÉTICOS HG - REPORTE DE VENTAS'), findsOneWidget);
    expect(find.textContaining('Subir facturas'), findsOneWidget);
    expect(find.text('Descargar PDF'), findsOneWidget);
  });
}
