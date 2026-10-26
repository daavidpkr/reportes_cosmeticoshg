import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/billing_customer.dart';
import '../models/customer_history.dart';
import '../models/invoice_status.dart';
import '../services/customer_history_repository.dart';
import 'reporte/report_invoice_table.dart';

typedef CustomerInvoiceDetail = Future<void> Function(
  CustomerHistoryInvoice invoice,
  BillingCustomer customer,
);

class CustomerHistoryScreen extends StatefulWidget {
  const CustomerHistoryScreen(
      {required this.customer,
      required this.onEditTerm,
      required this.onEditHours,
      required this.onSchedule,
      required this.onDelete,
      this.onOpenInvoiceDetail,
      this.onToggleTheme,
      this.repository,
      super.key});
  final BillingCustomer customer;
  final CustomerHistoryDataSource? repository;
  final Future<int?> Function(BillingCustomer) onEditTerm;
  final Future<BillingCustomer> Function(BillingCustomer, String?) onEditHours;
  final Future<void> Function(BillingCustomer) onSchedule;
  final Future<bool> Function(BillingCustomer) onDelete;
  final CustomerInvoiceDetail? onOpenInvoiceDetail;
  final VoidCallback? onToggleTheme;
  @override
  State<CustomerHistoryScreen> createState() => _CustomerHistoryScreenState();
}

class _CustomerHistoryScreenState extends State<CustomerHistoryScreen> {
  late final CustomerHistoryDataSource repository =
      widget.repository ?? CustomerHistoryRepository();
  CustomerContactDataSource? get contactRepository =>
      repository is CustomerContactDataSource
          ? repository as CustomerContactDataSource
          : null;
  final searchController = TextEditingController();
  Timer? debounce;
  CustomerHistorySummary? summary;
  final invoices = <CustomerHistoryInvoice>[];
  String status = 'all', sort = 'recent';
  int filteredCount = 0;
  bool loading = false, loadingMore = false;
  String? error;
  late BillingCustomer customer = widget.customer;
  bool actionBusy = false;
  int _loadGeneration = 0;
  String? _activeRequestKey;

  Future<CustomerHistoryPage> _loadHistoryPage(int offset) async {
    final terms = searchController.text
        .split(',')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    if (terms.length <= 1) {
      return repository.load(
        customerId: customer.id,
        offset: offset,
        status: status,
        search: terms.firstOrNull ?? '',
        sort: sort,
      );
    }
    final pages = await Future.wait([
      for (final term in terms)
        repository.load(
          customerId: customer.id,
          offset: offset,
          status: status,
          search: term,
          sort: sort,
        ),
    ]);
    final unique = <String, CustomerHistoryInvoice>{};
    for (final invoice in pages.expand((page) => page.invoices)) {
      unique['${invoice.reportMonth}\u0000${invoice.reference}'] = invoice;
    }
    final first = pages.first;
    return CustomerHistoryPage(
      summary: first.summary,
      invoices: unique.values.toList(growable: false),
      filteredCount: pages.fold(0, (sum, page) => sum + page.filteredCount),
      customer: first.customer,
    );
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _loadGeneration++;
    debounce?.cancel();
    searchController.dispose();
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    final offset = more ? invoices.length : 0;
    final requestKey = [
      customer.id,
      offset,
      status,
      searchController.text.trim(),
      sort,
    ].join('|');
    if (_activeRequestKey == requestKey) return;
    final generation = ++_loadGeneration;
    _activeRequestKey = requestKey;
    setState(() {
      if (more) {
        loadingMore = true;
      } else {
        loading = true;
        error = null;
      }
    });
    try {
      final page = await _loadHistoryPage(offset);
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        if (page.customer != null) {
          customer = BillingCustomer.fromJson(page.customer!);
        }
        summary = page.summary;
        filteredCount = page.filteredCount;
        if (!more) invoices.clear();
        invoices.addAll(page.invoices);
      });
    } catch (_) {
      if (mounted && generation == _loadGeneration) {
        setState(() => error = 'No se pudo cargar el historial.');
      }
    } finally {
      if (mounted && generation == _loadGeneration) {
        setState(() {
          loading = false;
          loadingMore = false;
        });
        _activeRequestKey = null;
      }
    }
  }

  Future<void> _refreshPreservingView() async {
    final generation = ++_loadGeneration;
    _activeRequestKey = 'refresh-preserving-$generation';
    final targetCount = invoices.length.clamp(25, 1 << 31);
    try {
      final refreshed = <CustomerHistoryInvoice>[];
      CustomerHistoryPage? firstPage;
      while (refreshed.length < targetCount) {
        final page = await _loadHistoryPage(refreshed.length);
        firstPage ??= page;
        refreshed.addAll(page.invoices);
        if (page.invoices.isEmpty || refreshed.length >= page.filteredCount) {
          break;
        }
      }
      if (!mounted || generation != _loadGeneration || firstPage == null) {
        return;
      }
      final currentPage = firstPage;
      setState(() {
        if (currentPage.customer != null) {
          customer = BillingCustomer.fromJson(currentPage.customer!);
        }
        summary = currentPage.summary;
        filteredCount = currentPage.filteredCount;
        invoices
          ..clear()
          ..addAll(refreshed);
        error = null;
      });
    } catch (_) {
      if (mounted && generation == _loadGeneration) {
        setState(() => error = 'No se pudo actualizar el historial.');
      }
    } finally {
      if (generation == _loadGeneration) _activeRequestKey = null;
    }
  }

  Future<void> _openInvoice(CustomerHistoryInvoice invoice) async {
    final callback = widget.onOpenInvoiceDetail;
    if (callback == null) return;
    await callback(invoice, customer);
    if (mounted) await _refreshPreservingView();
  }

  void _search(String _) {
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 350), _load);
  }

  Future<void> _editTerm() async {
    if (actionBusy || !customer.configurationActive) return;
    setState(() => actionBusy = true);
    try {
      final days = await widget.onEditTerm(customer);
      if (days != null && mounted) {
        setState(() => customer = customer.copyWith(paymentTermDays: days));
        await _load();
      }
    } finally {
      if (mounted) setState(() => actionBusy = false);
    }
  }

  Future<void> _editContact() async {
    final source = contactRepository;
    if (actionBusy || !customer.configurationActive || source == null) return;
    final updated = await showDialog<BillingCustomer>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ContactDialog(
        customer: customer,
        onSave: (address, phone, email) async => BillingCustomer.fromJson(
          await source.updateContact(
            customerId: customer.id,
            address: address,
            phone: phone,
            email: email,
          ),
        ),
      ),
    );
    if (updated == null || !mounted) return;
    setState(() => customer = updated);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Información de contacto actualizada.')),
    );
  }

  Future<void> _editHours() async {
    if (actionBusy || !customer.configurationActive) return;
    final updated = await showDialog<BillingCustomer>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _BusinessHoursDialog(
            customer: customer,
            onSave: (value) => widget.onEditHours(customer, value)));
    if (updated == null || !mounted) return;
    await _load();
    if (!mounted) return;
    if (customer.businessHours != updated.businessHours) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No se pudo verificar el horario guardado.')));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Horario de atención guardado.')));
  }

  Future<void> _schedule() async {
    if (actionBusy || !customer.configured) return;
    setState(() => actionBusy = true);
    try {
      await widget.onSchedule(customer);
      await _load();
    } finally {
      if (mounted) setState(() => actionBusy = false);
    }
  }

  Future<void> _delete() async {
    if (actionBusy) return;
    setState(() => actionBusy = true);
    try {
      if (await widget.onDelete(customer) && mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => actionBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewport = MediaQuery.sizeOf(context);
    final colors = Theme.of(context).colorScheme;
    return Dialog(
      insetPadding: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        child: SizedBox(
          width: viewport.width,
          height: viewport.height,
          child: Column(children: [
            Material(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              child: Padding(
                padding:
                    EdgeInsets.fromLTRB(viewport.width < 620 ? 6 : 22, 8, 8, 8),
                child: Row(children: [
                  IconButton(
                      tooltip: 'Regresar',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back)),
                  Expanded(
                      child: Text('Perfil del Cliente',
                          style: Theme.of(context).textTheme.titleLarge)),
                  if (widget.onToggleTheme != null)
                    IconButton(
                        tooltip: 'Cambiar tema',
                        onPressed: widget.onToggleTheme,
                        icon: Icon(
                            Theme.of(context).brightness == Brightness.dark
                                ? Icons.light_mode_outlined
                                : Icons.dark_mode_outlined)),
                  IconButton(
                      tooltip: 'Cerrar Perfil del Cliente',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close))
                ]),
              ),
            ),
            Expanded(child: LayoutBuilder(builder: (context, box) {
              final wide = box.maxWidth >= 1000;
              return RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: EdgeInsets.all(wide ? 24 : 14),
                  children: [
                    _Header(
                      customer: customer,
                      invoiceCount: summary?.totalInvoices,
                      onEditContact:
                          contactRepository == null ? null : _editContact,
                    ),
                    const SizedBox(height: 18),
                    if (wide)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 13,
                            child: _ContactPanel(
                              customer: customer,
                              onEdit: contactRepository == null
                                  ? null
                                  : _editContact,
                            ),
                          ),
                          const SizedBox(width: 18),
                          Expanded(
                            flex: 10,
                            child: _ConfigurationPanel(
                              customer: customer,
                              busy: actionBusy,
                              onEditTerm: _editTerm,
                              onEditHours: _editHours,
                              onSchedule:
                                  customer.configured ? _schedule : null,
                            ),
                          ),
                        ],
                      )
                    else
                      Column(
                        children: [
                          _ContactPanel(
                            customer: customer,
                            onEdit:
                                contactRepository == null ? null : _editContact,
                          ),
                          const SizedBox(height: 18),
                          _ConfigurationPanel(
                            customer: customer,
                            busy: actionBusy,
                            onEditTerm: _editTerm,
                            onEditHours: _editHours,
                            onSchedule: customer.configured ? _schedule : null,
                          ),
                        ],
                      ),
                    const SizedBox(height: 16),
                    if (loading && summary == null)
                      const Padding(
                          padding: EdgeInsets.all(60),
                          child: Center(child: CircularProgressIndicator()))
                    else if (error != null && summary == null)
                      _ErrorState(message: error!, retry: _load)
                    else ...[
                      if (error != null) ...[
                        _ErrorState(message: error!, retry: _load),
                        const SizedBox(height: 12),
                      ],
                      _Kpis(summary: summary!, wide: wide),
                      const SizedBox(height: 18),
                      _DebtSummary(
                        summary: summary!,
                        onSchedule: customer.configured &&
                                customer.configurationActive &&
                                summary!.pendingInvoices > 0
                            ? _schedule
                            : null,
                      ),
                      const SizedBox(height: 18),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: colors.surface,
                          borderRadius: BorderRadius.circular(21),
                          border: Border.all(color: colors.outlineVariant),
                        ),
                        child: Padding(
                          padding: EdgeInsets.all(wide ? 22 : 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(children: [
                                Text('Historial de facturas',
                                    style:
                                        Theme.of(context).textTheme.titleLarge),
                                const SizedBox(width: 10),
                                Chip(label: Text('$filteredCount registros')),
                              ]),
                              const SizedBox(height: 14),
                              _toolbar(wide),
                              const SizedBox(height: 12),
                              if (invoices.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.all(40),
                                  child: Center(
                                      child: Text(searchController
                                                  .text.isEmpty &&
                                              status == 'all'
                                          ? 'Este cliente todavía no tiene facturas asociadas.'
                                          : 'No se encontraron facturas con estos filtros.')),
                                )
                              else
                                for (final invoice in invoices)
                                  _InvoiceCard(
                                      invoice: invoice,
                                      onOpenDetail:
                                          widget.onOpenInvoiceDetail == null
                                              ? null
                                              : () => _openInvoice(invoice)),
                              if (invoices.length < filteredCount)
                                Center(
                                    child: FilledButton.tonal(
                                  onPressed: loadingMore
                                      ? null
                                      : () => _load(more: true),
                                  child: loadingMore
                                      ? const SizedBox.square(
                                          dimension: 18,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2))
                                      : const Text('Cargar más'),
                                )),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Align(
                        alignment: Alignment.centerRight,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                              foregroundColor: colors.error,
                              side: BorderSide(color: colors.error)),
                          onPressed: actionBusy || !customer.configurationActive
                              ? null
                              : _delete,
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Eliminar cliente'),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            }))
          ]),
        ),
      ),
    );
  }

  Widget _toolbar(bool wide) {
    final search = TextField(
      key: const ValueKey('customer-history-search'),
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
        'partial': 'Abonadas (${counts?.partialInvoices ?? 0})',
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
  const _Header(
      {required this.customer,
      required this.invoiceCount,
      required this.onEditContact});
  final BillingCustomer customer;
  final int? invoiceCount;
  final VoidCallback? onEditContact;
  String get initials {
    final code = RegExp(r'^N\d+', caseSensitive: false)
        .firstMatch(customer.name.trim())
        ?.group(0);
    if (code != null) return code.toUpperCase();
    return customer.name
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .take(2)
        .map((word) => word[0])
        .join()
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 620 ? 18 : 28),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          theme.colorScheme.surface,
          theme.colorScheme.surfaceContainerHigh
        ]),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: theme.colorScheme.outlineVariant),
        boxShadow: const [
          BoxShadow(
              color: Color(0x26000000), blurRadius: 28, offset: Offset(0, 12))
        ],
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
            width: 68,
            height: 68,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFFBB285D), Color(0xFF551A50)]),
                borderRadius: BorderRadius.circular(20)),
            child: Text(initials,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800))),
        const SizedBox(width: 18),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(customer.name,
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(
              customer.commercialName.isEmpty
                  ? 'Sin nombre comercial'
                  : customer.commercialName,
              style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _Badge(
                label: customer.configurationActive
                    ? '● Cliente activo'
                    : 'Cliente inactivo',
                active: customer.configurationActive),
            _Badge(
                label: invoiceCount == null
                    ? 'Cargando facturas…'
                    : '$invoiceCount facturas'),
            if (customer.contactInvoiceDate != null)
              const _Badge(label: 'Datos desde última factura'),
          ]),
          if (!customer.configurationActive) ...[
            const SizedBox(height: 10),
            const Text('El cliente ya no está disponible para edición.'),
          ],
        ])),
        if (onEditContact != null)
          IconButton.filledTonal(
              tooltip: 'Editar contacto',
              onPressed: onEditContact,
              icon: const Icon(Icons.edit_outlined)),
      ]),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, this.active = false});
  final String label;
  final bool active;
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
          color: active
              ? const Color(0x1600E676)
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          border: Border.all(
              color: active
                  ? const Color(0xFF00B85C)
                  : Theme.of(context).colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(99)),
      child: Text(label,
          style: TextStyle(
              color: active
                  ? const Color(0xFF00B85C)
                  : Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
              fontWeight: FontWeight.w700)));
}

class _ContactPanel extends StatelessWidget {
  const _ContactPanel({required this.customer, required this.onEdit});
  final BillingCustomer customer;
  final VoidCallback? onEdit;
  @override
  Widget build(BuildContext context) => _Panel(
      title: 'Información de contacto',
      icon: Icons.contact_page_outlined,
      trailing: TextButton(onPressed: onEdit, child: const Text('Editar')),
      child: Wrap(spacing: 12, runSpacing: 12, children: [
        _ContactItem(
            label: 'Dirección',
            value: customer.address,
            icon: Icons.location_on_outlined,
            wide: true),
        _ContactItem(
            label: 'Teléfono',
            value: customer.phone,
            icon: Icons.phone_outlined),
        _ContactItem(
            label: 'Correo electrónico',
            value: customer.email,
            icon: Icons.email_outlined),
      ]));
}

class _ContactItem extends StatelessWidget {
  const _ContactItem(
      {required this.label,
      required this.value,
      required this.icon,
      this.wide = false});
  final String label;
  final String? value;
  final IconData icon;
  final bool wide;
  @override
  Widget build(BuildContext context) => Container(
      width: wide ? double.infinity : 260,
      constraints: const BoxConstraints(minHeight: 72),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(15),
          border:
              Border.all(color: Theme.of(context).colorScheme.outlineVariant)),
      child: Row(children: [
        Icon(icon, size: 20),
        const SizedBox(width: 10),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label.toUpperCase(),
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 11,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 5),
          Text(value ?? 'Sin registrar',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600))
        ]))
      ]));
}

class _ConfigurationPanel extends StatelessWidget {
  const _ConfigurationPanel(
      {required this.customer,
      required this.busy,
      required this.onEditTerm,
      required this.onEditHours,
      required this.onSchedule});
  final BillingCustomer customer;
  final bool busy;
  final VoidCallback onEditTerm, onEditHours;
  final VoidCallback? onSchedule;
  @override
  Widget build(BuildContext context) => _Panel(
      title: 'Configuración de cobro',
      icon: Icons.tune,
      child: Column(children: [
        _ConfigRow(
            icon: Icons.schedule_outlined,
            title: customer.paymentTermDays == null
                ? 'Plazo pendiente'
                : 'Plazo de pago: ${customer.paymentTermDays} días',
            subtitle: 'Plazo habitual de pago',
            buttonLabel: 'Editar plazo',
            onEdit: busy || !customer.configurationActive ? null : onEditTerm),
        const SizedBox(height: 12),
        _ConfigRow(
            icon: Icons.access_time,
            title:
                'Horario de atención: ${customer.businessHours ?? 'Sin registrar'}',
            subtitle: 'Horario de atención',
            buttonLabel: 'Editar horario',
            onEdit: busy || !customer.configurationActive ? null : onEditHours),
        const SizedBox(height: 14),
        Tooltip(
            message: customer.configured
                ? 'Programar facturas pendientes'
                : 'Configura primero los días de pago',
            child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                    onPressed: busy || !customer.configurationActive
                        ? null
                        : onSchedule,
                    icon: const Icon(Icons.event_repeat_outlined),
                    label: const Text('Programar pendientes')))),
      ]));
}

class _Panel extends StatelessWidget {
  const _Panel(
      {required this.title,
      required this.icon,
      required this.child,
      this.trailing});
  final String title;
  final IconData icon;
  final Widget child;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border:
              Border.all(color: Theme.of(context).colorScheme.outlineVariant)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(icon),
          const SizedBox(width: 10),
          Expanded(
              child: Text(title,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700))),
          if (trailing != null) trailing!
        ]),
        const SizedBox(height: 18),
        child
      ]));
}

class _ConfigRow extends StatelessWidget {
  const _ConfigRow(
      {required this.icon,
      required this.title,
      required this.subtitle,
      required this.buttonLabel,
      required this.onEdit});
  final IconData icon;
  final String title, subtitle;
  final String buttonLabel;
  final VoidCallback? onEdit;
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(15)),
      child: Row(children: [
        Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(11)),
            child: Icon(icon, size: 20)),
        const SizedBox(width: 12),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          Text(subtitle,
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12))
        ])),
        OutlinedButton(
            style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(horizontal: 8)),
            onPressed: onEdit,
            child: Text(buttonLabel))
      ]));
}

class _ContactDialog extends StatefulWidget {
  const _ContactDialog({required this.customer, required this.onSave});
  final BillingCustomer customer;
  final Future<BillingCustomer> Function(String, String, String) onSave;
  @override
  State<_ContactDialog> createState() => _ContactDialogState();
}

class _ContactDialogState extends State<_ContactDialog> {
  late final address =
      TextEditingController(text: widget.customer.address ?? '');
  late final phone = TextEditingController(text: widget.customer.phone ?? '');
  late final email = TextEditingController(text: widget.customer.email ?? '');
  bool saving = false;
  String? error;

  @override
  void dispose() {
    address.dispose();
    phone.dispose();
    email.dispose();
    super.dispose();
  }

  bool get changed =>
      address.text.trim() != (widget.customer.address ?? '') ||
      phone.text.trim() != (widget.customer.phone ?? '') ||
      email.text.trim().toLowerCase() != (widget.customer.email ?? '');
  bool get validPhone =>
      phone.text.trim().isEmpty ||
      RegExp(r'^\+?[0-9]{7,15}$').hasMatch(phone.text.trim());
  bool get validEmail =>
      email.text.trim().isEmpty ||
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email.text.trim());

  Future<void> save() async {
    if (saving || !changed || !validPhone || !validEmail) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final result = await widget.onSave(address.text.trim(), phone.text.trim(),
          email.text.trim().toLowerCase());
      if (mounted) {
        Navigator.pop(context, result);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          saving = false;
          error =
              'No se pudo guardar la información. Revisa los datos e inténtalo nuevamente.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Editar información de contacto'),
        content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                  TextField(
                      key: const ValueKey('customer-contact-address'),
                      controller: address,
                      enabled: !saving,
                      maxLength: 500,
                      maxLines: 2,
                      decoration:
                          const InputDecoration(labelText: 'Dirección')),
                  const SizedBox(height: 10),
                  TextField(
                      key: const ValueKey('customer-contact-phone'),
                      controller: phone,
                      enabled: !saving,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[+0-9]'))
                      ],
                      maxLength: 16,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                          labelText: 'Teléfono',
                          errorText:
                              validPhone ? null : 'Usa entre 7 y 15 dígitos.')),
                  const SizedBox(height: 10),
                  TextField(
                      key: const ValueKey('customer-contact-email'),
                      controller: email,
                      enabled: !saving,
                      keyboardType: TextInputType.emailAddress,
                      maxLength: 254,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                          labelText: 'Correo electrónico',
                          errorText:
                              validEmail ? null : 'Ingresa un correo válido.')),
                  Text(
                      'Estos datos corresponden al cliente canónico. La identificación interna no se muestra.',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 12)),
                  if (error != null)
                    Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(error!,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error))),
                ]))),
        actions: [
          TextButton(
              onPressed: saving ? null : () => Navigator.pop(context),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: saving || !changed || !validPhone || !validEmail
                  ? null
                  : save,
              child: saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Guardar cambios')),
        ],
      );
}

class _BusinessHoursDialog extends StatefulWidget {
  const _BusinessHoursDialog({required this.customer, required this.onSave});
  final BillingCustomer customer;
  final Future<BillingCustomer> Function(String?) onSave;

  @override
  State<_BusinessHoursDialog> createState() => _BusinessHoursDialogState();
}

class _BusinessHoursDialogState extends State<_BusinessHoursDialog> {
  late final TextEditingController controller =
      TextEditingController(text: widget.customer.businessHours ?? '');
  bool saving = false;
  String? error;

  String? get normalized {
    final value = controller.text.trim();
    return value.isEmpty ? null : value;
  }

  bool get changed => normalized != widget.customer.businessHours;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (saving || !changed || controller.text.length > 120) return;
    if (normalized == null && widget.customer.businessHours != null) {
      final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                title: const Text('Quitar horario'),
                content: const Text(
                    'El horario actual se eliminará. ¿Deseas continuar?'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancelar')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Quitar horario')),
                ],
              ));
      if (confirmed != true || !mounted) return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final result = await widget.onSave(normalized);
      if (mounted) Navigator.pop(context, result);
    } catch (_) {
      if (mounted) {
        setState(() {
          saving = false;
          error = 'No se pudo guardar el horario. Inténtalo nuevamente.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Editar horario de atención'),
        content: SizedBox(
          width: 480,
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.customer.name,
                    style: Theme.of(context).textTheme.titleMedium),
                Text(
                    'Horario actual: ${widget.customer.businessHours ?? 'Sin registrar'}'),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  enabled: !saving,
                  maxLength: 120,
                  maxLines: 3,
                  onChanged: (_) => setState(() => error = null),
                  decoration: InputDecoration(
                      labelText: 'Horario de atención',
                      hintText: 'Lunes a viernes, 09:00 - 17:00',
                      errorText: error),
                  onSubmitted: (_) => save(),
                ),
              ]),
        ),
        actions: [
          TextButton(
              onPressed: saving ? null : () => Navigator.pop(context),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: saving || !changed || controller.text.length > 120
                  ? null
                  : save,
              child: saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Guardar')),
        ],
      );
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
              height: wide ? 100 : 116,
              child: Card(
                  child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(item.$1,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center),
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
  const _DebtSummary({required this.summary, required this.onSchedule});
  final CustomerHistorySummary summary;
  final VoidCallback? onSchedule;
  String date(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
  @override
  Widget build(BuildContext context) => Container(
      decoration: BoxDecoration(
        color: summary.balance <= .005
            ? const Color(0x1200E676)
            : const Color(0x12FF1744),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(
            color: summary.balance <= .005
                ? const Color(0xFF00B85C)
                : const Color(0xFFFF1744)),
      ),
      child: ListTile(
          leading: Icon(summary.balance <= .005
              ? Icons.verified_outlined
              : Icons.account_balance_wallet_outlined),
          title: Text(summary.balance <= .005
              ? 'Cliente al día'
              : 'Deuda pendiente: \$${summary.balance.toStringAsFixed(2)}'),
          subtitle: Text(summary.balance <= .005
              ? 'Sin deuda pendiente'
              : '${summary.pendingInvoices} facturas pendientes · ${summary.overdueInvoices} vencidas\n${summary.nextPayment == null ? 'Sin próximo cobro programado' : 'Próximo cobro: ${date(summary.nextPayment!)}'}'),
          trailing: onSchedule == null
              ? null
              : FilledButton(
                  onPressed: onSchedule,
                  child: const Text('Programar cobro'))));
}

class _InvoiceCard extends StatelessWidget {
  const _InvoiceCard({required this.invoice, this.onOpenDetail});
  final CustomerHistoryInvoice invoice;
  final VoidCallback? onOpenDetail;
  String money(double v) => '\$${v.toStringAsFixed(2)}';
  String date(DateTime v) =>
      '${v.day.toString().padLeft(2, '0')}/${v.month.toString().padLeft(2, '0')}/${v.year}';

  ReportInvoiceRowStatus get rowStatus =>
      reportRowStatus(invoice.semanticStatus);

  @override
  Widget build(BuildContext context) {
    final background = reportInvoiceRowBackground(context, rowStatus);
    final shape = rowStatus == ReportInvoiceRowStatus.normal
        ? null
        : RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: reportInvoiceRowBorder(context, rowStatus),
              width: 1.4,
            ),
          );
    return Card(
      key: ValueKey('customer-invoice-${invoice.reference}'),
      color: background,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpenDetail,
        child: Padding(
            padding: const EdgeInsets.all(16),
            child: LayoutBuilder(builder: (context, box) {
              final compact = box.maxWidth < 700;
              final identity = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Factura ${invoice.invoiceNumber}',
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text('Ref. ${invoice.reference}',
                        style: TextStyle(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                            fontSize: 12))
                  ]);
              final issued = _InvoiceDatum(
                  label: 'Fecha de emisión', value: date(invoice.date));
              final collection = _InvoiceDatum(
                  label: invoice.reminderDate == null
                      ? 'Próximo cobro'
                      : 'Fecha de cobro',
                  value: invoice.reminderDate == null
                      ? 'Sin programar'
                      : date(invoice.reminderDate!));
              final paid =
                  _InvoiceDatum(label: 'Abonado', value: money(invoice.paid));
              final amount =
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(money(invoice.balance),
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                _StatusPill(invoice: invoice)
              ]);
              if (compact) {
                return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            identity,
                            const SizedBox(height: 10),
                            issued,
                            const SizedBox(height: 6),
                            collection,
                            const SizedBox(height: 6),
                            paid
                          ])),
                      const SizedBox(width: 12),
                      amount,
                      const SizedBox(width: 4),
                      const Icon(Icons.chevron_right)
                    ]);
              }
              return Row(children: [
                Expanded(flex: 14, child: identity),
                Expanded(flex: 9, child: issued),
                Expanded(flex: 9, child: collection),
                Expanded(flex: 8, child: paid),
                amount,
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right)
              ]);
            })),
      ),
    );
  }
}

class _InvoiceDatum extends StatelessWidget {
  const _InvoiceDatum({required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label.toUpperCase(),
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 10,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 3),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600))
      ]);
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.invoice});
  final CustomerHistoryInvoice invoice;
  @override
  Widget build(BuildContext context) {
    final color = invoiceStatusBorder(
      Theme.of(context).brightness,
      invoice.semanticStatus,
    );
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
            color: invoiceStatusBackground(context, invoice.semanticStatus),
            border: Border.all(color: color),
            borderRadius: BorderRadius.circular(99)),
        child: Text(invoice.status,
            style: TextStyle(
                color: color, fontSize: 11, fontWeight: FontWeight.w800)));
  }
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
