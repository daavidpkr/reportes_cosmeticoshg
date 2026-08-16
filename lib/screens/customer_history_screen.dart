import 'dart:async';

import 'package:flutter/material.dart';

import '../models/billing_customer.dart';
import '../models/customer_history.dart';
import '../services/customer_history_repository.dart';

class CustomerHistoryScreen extends StatefulWidget {
  const CustomerHistoryScreen(
      {required this.customer, this.repository, super.key});
  final BillingCustomer customer;
  final CustomerHistoryDataSource? repository;
  @override
  State<CustomerHistoryScreen> createState() => _CustomerHistoryScreenState();
}

class _CustomerHistoryScreenState extends State<CustomerHistoryScreen> {
  late final CustomerHistoryDataSource repository =
      widget.repository ?? CustomerHistoryRepository();
  final searchController = TextEditingController();
  Timer? debounce;
  CustomerHistorySummary? summary;
  final invoices = <CustomerHistoryInvoice>[];
  String status = 'all', sort = 'recent';
  int filteredCount = 0;
  bool loading = false, loadingMore = false;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    debounce?.cancel();
    searchController.dispose();
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    if (more ? loadingMore : loading) return;
    setState(() {
      if (more) {
        loadingMore = true;
      } else {
        loading = true;
        error = null;
      }
    });
    try {
      final page = await repository.load(
        customerId: widget.customer.id,
        offset: more ? invoices.length : 0,
        status: status,
        search: searchController.text,
        sort: sort,
      );
      if (!mounted) return;
      setState(() {
        summary = page.summary;
        filteredCount = page.filteredCount;
        if (!more) invoices.clear();
        invoices.addAll(page.invoices);
      });
    } catch (_) {
      if (mounted) {
        setState(() => error = 'No se pudo cargar el historial.');
      }
    } finally {
      if (mounted) {
        setState(() {
          loading = false;
          loadingMore = false;
        });
      }
    }
  }

  void _search(String _) {
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 350), _load);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Historial del cliente')),
        body: SafeArea(child: LayoutBuilder(builder: (context, box) {
          final wide = box.maxWidth >= 760;
          return RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: EdgeInsets.all(wide ? 24 : 14),
              children: [
                _Header(customer: widget.customer),
                const SizedBox(height: 16),
                if (loading && summary == null)
                  const Padding(
                      padding: EdgeInsets.all(60),
                      child: Center(child: CircularProgressIndicator()))
                else if (error != null && summary == null)
                  _ErrorState(message: error!, retry: _load)
                else ...[
                  _Kpis(summary: summary!, wide: wide),
                  const SizedBox(height: 12),
                  _DebtSummary(summary: summary!),
                  const SizedBox(height: 16),
                  _toolbar(wide),
                  const SizedBox(height: 12),
                  if (invoices.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(40),
                      child: Center(
                          child: Text(searchController.text.isEmpty &&
                                  status == 'all'
                              ? 'Este cliente todavía no tiene facturas registradas.'
                              : 'No se encontraron facturas con estos filtros.')),
                    )
                  else
                    for (final invoice in invoices)
                      _InvoiceCard(invoice: invoice),
                  if (invoices.length < filteredCount)
                    Center(
                        child: FilledButton.tonal(
                      onPressed: loadingMore ? null : () => _load(more: true),
                      child: loadingMore
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Cargar más'),
                    )),
                ],
              ],
            ),
          );
        })),
      );

  Widget _toolbar(bool wide) {
    final search = TextField(
      controller: searchController,
      onChanged: _search,
      decoration: const InputDecoration(
          prefixIcon: Icon(Icons.search), hintText: 'Buscar factura'),
    );
    final counts = summary;
    final controls = Wrap(spacing: 8, runSpacing: 8, children: [
      for (final item in {
        'all': 'Todas (${counts?.totalInvoices ?? 0})',
        'pending': 'Pendientes (${counts?.pendingInvoices ?? 0})',
        'paid': 'Pagadas (${counts?.paidInvoices ?? 0})',
        'overdue': 'Vencidas (${counts?.overdueInvoices ?? 0})',
        'cancelled': 'Anuladas (${counts?.cancelledInvoices ?? 0})'
      }.entries)
        ChoiceChip(
            label: Text(item.value),
            selected: status == item.key,
            onSelected: (_) {
              setState(() => status = item.key);
              _load();
            }),
      DropdownButton<String>(
          value: sort,
          items: const [
            DropdownMenuItem(value: 'recent', child: Text('Más recientes')),
            DropdownMenuItem(value: 'oldest', child: Text('Más antiguas')),
            DropdownMenuItem(value: 'sale', child: Text('Mayor venta')),
            DropdownMenuItem(value: 'balance', child: Text('Mayor saldo')),
          ],
          onChanged: (value) {
            if (value != null) {
              setState(() => sort = value);
              _load();
            }
          }),
    ]);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      search,
      const SizedBox(height: 10),
      if (wide)
        controls
      else
        SingleChildScrollView(scrollDirection: Axis.horizontal, child: controls)
    ]);
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.customer});
  final BillingCustomer customer;
  @override
  Widget build(BuildContext context) => Card(
      child: Padding(
          padding: const EdgeInsets.all(18),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(customer.name, style: Theme.of(context).textTheme.titleLarge),
            Text(customer.commercialName.isEmpty
                ? 'Sin nombre comercial'
                : customer.commercialName),
            const SizedBox(height: 8),
            Text(customer.paymentTermDays == null
                ? 'Plazo pendiente'
                : 'Plazo de pago: ${customer.paymentTermDays} días'),
          ])));
}

class _Kpis extends StatelessWidget {
  const _Kpis({required this.summary, required this.wide});
  final CustomerHistorySummary summary;
  final bool wide;
  @override
  Widget build(BuildContext context) {
    final items = [
      ('Total histórico', summary.totalSales),
      ('Total cobrado', summary.totalPaid),
      ('Deuda pendiente', summary.balance),
      ('Total de facturas', summary.totalInvoices.toDouble())
    ];
    return LayoutBuilder(builder: (context, constraints) {
      final width = wide
          ? (constraints.maxWidth - 24) / 4
          : (constraints.maxWidth - 8) / 2;
      return Wrap(spacing: 8, runSpacing: 8, children: [
        for (final item in items)
          SizedBox(
              width: width,
              height: 100,
              child: Card(
                  child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(item.$1, textAlign: TextAlign.center),
                            const SizedBox(height: 4),
                            FittedBox(
                                child: Text(
                                    item.$1 == 'Total de facturas'
                                        ? '${item.$2.toInt()}'
                                        : '\$${item.$2.toStringAsFixed(2)}',
                                    style:
                                        Theme.of(context).textTheme.titleLarge))
                          ]))))
      ]);
    });
  }
}

class _DebtSummary extends StatelessWidget {
  const _DebtSummary({required this.summary});
  final CustomerHistorySummary summary;
  String date(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
  @override
  Widget build(BuildContext context) => Card(
      child: ListTile(
          leading: Icon(summary.balance <= .005
              ? Icons.verified_outlined
              : Icons.account_balance_wallet_outlined),
          title: Text(summary.balance <= .005
              ? 'Cliente al día'
              : 'Deuda pendiente: \$${summary.balance.toStringAsFixed(2)}'),
          subtitle: Text(summary.balance <= .005
              ? 'Sin deuda pendiente'
              : '${summary.pendingInvoices} facturas pendientes · ${summary.overdueInvoices} vencidas\n${summary.nextPayment == null ? 'Sin próximo cobro programado' : 'Próximo cobro: ${date(summary.nextPayment!)}'}')));
}

class _InvoiceCard extends StatelessWidget {
  const _InvoiceCard({required this.invoice});
  final CustomerHistoryInvoice invoice;
  String money(double v) => '\$${v.toStringAsFixed(2)}';
  String date(DateTime v) =>
      '${v.day.toString().padLeft(2, '0')}/${v.month.toString().padLeft(2, '0')}/${v.year}';
  @override
  Widget build(BuildContext context) => Card(
          child: ExpansionTile(
              title: Text('Factura ${invoice.invoiceNumber}'),
              subtitle: Text('${date(invoice.date)} · ${invoice.status}'),
              trailing: Text(money(invoice.balance),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              children: [
            Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          'REF. ${invoice.reference} · ${invoice.reportMonth}'),
                      Text(
                          'Vendedor: ${invoice.seller.isEmpty ? 'Sin registrar' : invoice.seller}'),
                      Text(
                          'Venta: ${money(invoice.sale)} · Abonado: ${money(invoice.paid)} · Saldo: ${money(invoice.balance)}'),
                      if (invoice.reminderDate != null)
                        Text('Fecha de cobro: ${date(invoice.reminderDate!)}'),
                      if (invoice.calendarComment.isNotEmpty)
                        Text(
                            'Comentario del calendario: ${invoice.calendarComment}'),
                      for (var i = 0; i < invoice.payments.length; i++)
                        Text(
                            'Abono ${i + 1}: ${money(invoice.payments[i].amount)} · Recibo: ${invoice.payments[i].receiptNumber ?? 'Sin recibo'}${invoice.payments[i].comment.isEmpty ? '' : ' · ${invoice.payments[i].comment}'}')
                    ]))
          ]));
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.retry});
  final String message;
  final VoidCallback retry;
  @override
  Widget build(BuildContext context) => Center(
          child: Column(children: [
        Text(message),
        TextButton(onPressed: retry, child: const Text('Reintentar'))
      ]));
}
