import 'package:cosmeticos_hg_reportes/models/billing_customer.dart';
import 'package:cosmeticos_hg_reportes/models/customer_history.dart';
import 'package:cosmeticos_hg_reportes/models/fila_venta.dart';
import 'package:cosmeticos_hg_reportes/screens/customer_history_screen.dart';
import 'package:cosmeticos_hg_reportes/screens/invoice_detail_dialog.dart';
import 'package:cosmeticos_hg_reportes/services/customer_history_repository.dart';
import 'package:cosmeticos_hg_reportes/theme/hg_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _HistoryRepository
    implements CustomerHistoryDataSource, CustomerContactDataSource {
  int loads = 0;
  Map<String, String>? savedContact;

  static final invoices = [
    _invoice('PENDING', sale: 100, paid: 0),
    _invoice('PARTIAL', sale: 100, paid: 25),
    _invoice('PAID', sale: 100, paid: 100),
    _invoice('CANCELLED', sale: 100, paid: 0, cancelled: true),
  ];

  static CustomerHistoryInvoice _invoice(
    String reference, {
    required double sale,
    required double paid,
    bool cancelled = false,
  }) =>
      CustomerHistoryInvoice(
        reference: reference,
        invoiceNumber: reference,
        date: DateTime(2026, 10, 1),
        seller: cancelled ? 'ANULADA' : 'VENDEDOR',
        reportMonth: 'OCTUBRE 2026',
        sale: sale,
        paid: paid,
        balance: cancelled ? 0 : sale - paid,
        cancelled: cancelled,
        overdue: false,
        reminderDate: DateTime(2026, 10, 20),
        payments: paid == 0
            ? const []
            : [
                CustomerHistoryPayment(
                  amount: paid,
                  receiptNumber: 123,
                  comment: 'Abono de prueba',
                ),
              ],
      );

  @override
  Future<CustomerHistoryPage> load({
    required String customerId,
    required int offset,
    String status = 'all',
    String search = '',
    String sort = 'recent',
  }) async {
    loads++;
    return CustomerHistoryPage(
      summary: const CustomerHistorySummary(
        totalSales: 300,
        totalPaid: 125,
        balance: 175,
        totalInvoices: 4,
        paidInvoices: 1,
        pendingInvoices: 2,
        overdueInvoices: 0,
        cancelledInvoices: 1,
      ),
      invoices: invoices,
      filteredCount: invoices.length,
    );
  }

  @override
  Future<InvoiceTermRecalculation> previewRecalculation(String reference) =>
      throw UnimplementedError();

  @override
  Future<InvoiceTermRecalculation> reprogramInvoice(
          InvoiceTermRecalculation preview) =>
      throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> updateContact({
    required String customerId,
    required String address,
    required String phone,
    required String email,
  }) async {
    savedContact = {
      'customer_id': customerId,
      'address': address,
      'phone': phone,
      'email': email
    };
    return {
      'id': customerId,
      'name': _customer.name,
      'commercial_name': _customer.commercialName,
      'payment_term_days': _customer.paymentTermDays,
      'configuration_active': true,
      'address': address,
      'phone': phone,
      'email': email,
    };
  }
}

const _customer = BillingCustomer(
  id: 'customer',
  name: 'Cliente de prueba',
  commercialName: 'Local de prueba',
  paymentTermDays: 30,
  address: 'Dirección inicial',
  phone: '0991112222',
  email: 'inicial@ejemplo.com',
);

Widget _profile({
  required _HistoryRepository repository,
  required CustomerInvoiceDetail onOpenInvoiceDetail,
  ThemeMode themeMode = ThemeMode.light,
}) =>
    MaterialApp(
      themeMode: themeMode,
      theme:
          ThemeData.light().copyWith(extensions: const [HgThemeColors.light]),
      darkTheme:
          ThemeData.dark().copyWith(extensions: const [HgThemeColors.dark]),
      home: Scaffold(
        body: CustomerHistoryScreen(
          customer: _customer,
          repository: repository,
          onEditTerm: (_) async => null,
          onEditHours: (customer, value) async => customer,
          onSchedule: (_) async {},
          onDelete: (_) async => false,
          onOpenInvoiceDetail: onOpenInvoiceDetail,
        ),
      ),
    );

void main() {
  testWidgets(
      'contacto canónico se edita por customer_id sin mostrar identidad',
      (tester) async {
    final repository = _HistoryRepository();
    await tester.pumpWidget(_profile(
      repository: repository,
      onOpenInvoiceDetail: (_, __) async {},
    ));
    await tester.pumpAndSettle();
    expect(find.text('Dirección inicial'), findsOneWidget);
    expect(find.textContaining('identificación'), findsNothing);
    await tester.tap(find.byTooltip('Editar contacto'));
    await tester.pumpAndSettle();
    expect(find.textContaining('La identificación interna no se muestra.'),
        findsOneWidget);
    await tester.enterText(
        find.byKey(const ValueKey('customer-contact-address')),
        'Nueva avenida');
    await tester.enterText(
        find.byKey(const ValueKey('customer-contact-phone')), '0987654321');
    await tester.enterText(find.byKey(const ValueKey('customer-contact-email')),
        'NUEVO@EJEMPLO.COM');
    await tester.tap(find.text('Guardar cambios'));
    await tester.pumpAndSettle();
    expect(repository.savedContact, {
      'customer_id': 'customer',
      'address': 'Nueva avenida',
      'phone': '0987654321',
      'email': 'nuevo@ejemplo.com',
    });
    expect(find.text('Nueva avenida'), findsOneWidget);
  });

  testWidgets('tarjetas usan estados fluorescentes de la tabla',
      (tester) async {
    final repository = _HistoryRepository();
    await tester.pumpWidget(_profile(
      repository: repository,
      onOpenInvoiceDetail: (_, __) async {},
    ));
    await tester.pumpAndSettle();

    Card card(String reference) => tester
        .widget<Card>(find.byKey(ValueKey('customer-invoice-$reference')));
    RoundedRectangleBorder border(String reference) =>
        card(reference).shape! as RoundedRectangleBorder;

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('customer-invoice-PENDING')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(card('PENDING').color, isNull);
    expect(card('PENDING').shape, isNull);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('customer-invoice-PARTIAL')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(border('PARTIAL').side.color, const Color(0xFFFFC400));
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('customer-invoice-PAID')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(border('PAID').side.color, const Color(0xFF00E676));
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('customer-invoice-CANCELLED')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(border('CANCELLED').side.color, const Color(0xFFFF1744));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(_profile(
      repository: repository,
      onOpenInvoiceDetail: (_, __) async {},
      themeMode: ThemeMode.dark,
    ));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('customer-invoice-PARTIAL')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(border('PARTIAL').side.color, const Color(0xFFFFFF00));
  });

  testWidgets('tarjeta abre el detalle único y conserva el perfil al cerrar',
      (tester) async {
    final repository = _HistoryRepository();
    final navigatorKey = GlobalKey<NavigatorState>();
    late CustomerInvoiceDetail openDetail;
    openDetail = (invoice, customer) => showInvoiceDetailDialog(
          navigatorKey.currentContext!,
          invoice: FilaVenta(
            numero: 1,
            referencia: invoice.reference,
            cliente: customer.name,
            nombreComercial: customer.commercialName,
            fecha: '2026-10-01',
            numeroFactura: invoice.invoiceNumber,
            vendedor: invoice.seller,
            venta: invoice.sale,
            abonos: invoice.payments
                .map((payment) => Abono(
                      valor: payment.amount,
                      numeroRecibo: payment.receiptNumber,
                      comentario: payment.comment,
                    ))
                .toList(),
          ),
          scheduledDate: invoice.reminderDate,
          reportMonth: invoice.reportMonth,
          onPayment: () async {},
          onPayInFull: () async {},
          onReschedule: () async {},
        );

    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigatorKey,
      home: Scaffold(
        body: CustomerHistoryScreen(
          customer: _customer,
          repository: repository,
          onEditTerm: (_) async => null,
          onEditHours: (customer, value) async => customer,
          onSchedule: (_) async {},
          onDelete: (_) async => false,
          onOpenInvoiceDetail: openDetail,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final search = find.byKey(const ValueKey('customer-history-search'));
    await tester.scrollUntilVisible(
      search,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(search, 'factura');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('customer-invoice-PARTIAL')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester
        .ensureVisible(find.byKey(const ValueKey('customer-invoice-PARTIAL')));
    await tester.tap(find.byKey(const ValueKey('customer-invoice-PARTIAL')));
    await tester.pumpAndSettle();

    expect(find.text('Detalle de factura'), findsOneWidget);
    expect(find.text('PARTIAL'), findsWidgets);
    expect(find.text('Cliente de prueba'), findsWidgets);
    expect(find.text('Local de prueba'), findsWidgets);
    expect(find.text('OCTUBRE 2026'), findsOneWidget);
    expect(find.textContaining('Abono de prueba'), findsOneWidget);
    expect(find.text('Registrar abono'), findsOneWidget);
    expect(find.text('Pago completo'), findsOneWidget);
    expect(find.text('Reprogramar'), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(
            const ValueKey('view-customer-profile'),
          ))
          .onPressed,
      isNull,
    );

    await tester.tap(find.byTooltip('Cerrar'));
    await tester.pumpAndSettle();
    expect(find.text('Perfil del Cliente'), findsOneWidget);
    expect(tester.widget<TextField>(search).controller!.text, 'factura');
    expect(repository.loads, 3);
  });
}
