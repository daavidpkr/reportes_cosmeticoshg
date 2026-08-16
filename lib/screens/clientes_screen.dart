import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/billing_customer.dart';
import '../services/customer_terms_repository.dart';
import '../services/customer_history_repository.dart';
import 'customer_history_screen.dart';

class ClientesScreen extends StatefulWidget {
  const ClientesScreen({this.repository, this.historyRepository, super.key});
  final CustomerTermsDataSource? repository;
  final CustomerHistoryDataSource? historyRepository;
  @override
  State<ClientesScreen> createState() => _ClientesScreenState();
}

class _ClientesScreenState extends State<ClientesScreen> {
  late final CustomerTermsDataSource _repository =
      widget.repository ?? CustomerTermsRepository();
  late Future<List<BillingCustomer>> _customers = _repository.listCustomers();
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  Object? _selectedTerm;
  static const pendingTerm = 'pending';
  Future<void> _reload() async {
    final next = _repository.listCustomers();
    setState(() {
      _customers = next;
    });
    await next;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _normalizedSearch(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  List<Object> _terms(List<BillingCustomer> customers) {
    final numeric = customers
        .map((customer) => customer.paymentTermDays)
        .whereType<int>()
        .toSet()
        .toList()
      ..sort();
    return <Object>[
      ...numeric,
      if (customers.any((customer) => customer.paymentTermDays == null))
        pendingTerm,
    ];
  }

  bool _matches(BillingCustomer customer) {
    final query = _normalizedSearch(_query);
    final searchable =
        _normalizedSearch('${customer.name} ${customer.commercialName}');
    final matchesQuery = query.isEmpty || searchable.contains(query);
    final matchesTerm = _selectedTerm == null ||
        (_selectedTerm == pendingTerm
            ? customer.paymentTermDays == null
            : customer.paymentTermDays == _selectedTerm);
    return matchesQuery && matchesTerm;
  }

  void _clearFilters() {
    _searchController.clear();
    setState(() {
      _query = '';
      _selectedTerm = null;
    });
  }

  void _message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<int?> _edit(BillingCustomer c) async {
    final days = await showDialog<int>(
        context: context, builder: (_) => _PaymentTermDialog(customer: c));
    if (days == null || !mounted) return null;
    final impacted = await _repository.previewImpact(c.id, days);
    final count =
        await _repository.savePaymentTerm(c.id, days, applyExisting: true);
    _message(impacted == 0
        ? 'Plazo habitual guardado.'
        : 'Plazo guardado y $count facturas programadas.');
    await _reload();
    return days;
  }

  Future<bool> _delete(BillingCustomer c) async {
    final ok = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _OperationDialog(
            title: 'Eliminar cliente',
            customer: c,
            confirmLabel: 'Eliminar cliente',
            destructive: true,
            body:
                'Se eliminará a este cliente únicamente del apartado Clientes.\n\nLas facturas, abonos y recordatorios relacionados se conservarán sin cambios.',
            operation: () => _repository.deleteCustomer(c)));
    if (ok != true || !mounted) return false;
    _message(
        'Cliente eliminado del apartado Clientes. Sus facturas y recordatorios se conservaron.');
    await _reload();
    return true;
  }

  Future<void> _schedule(BillingCustomer c) async {
    CustomerSchedulingResult? result;
    final ok = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _OperationDialog(
            title: 'Programar facturas pendientes',
            customer: c,
            confirmLabel: 'Programar',
            body:
                'Se buscarán las facturas con saldo de este cliente que todavía no tengan recordatorio en el calendario.\n\nPlazo configurado: ${c.paymentTermDays} días\n\nLos recordatorios existentes no serán modificados.',
            operation: () async {
              result = await _repository.schedulePending(c);
            }));
    if (ok != true || result == null || !mounted) return;
    if (result!.createdCount == 0) {
      _message(
          'Todas las facturas elegibles de este cliente ya están programadas.');
    } else if (result!.skippedCount > 0) {
      _message(
          'Se programaron ${result!.createdCount} facturas. Otras ${result!.skippedCount} no cumplían las condiciones.');
    } else {
      _message(
          'Se programaron ${result!.createdCount} facturas pendientes en el calendario.');
    }
    await _reload();
  }

  Future<void> _openHistory(BillingCustomer customer) => showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => CustomerHistoryScreen(
          customer: customer,
          repository: widget.historyRepository,
          onEditTerm: _edit,
          onSchedule: _schedule,
          onDelete: _delete));

  @override
  Widget build(BuildContext context) => RefreshIndicator(
      onRefresh: _reload,
      child: FutureBuilder<List<BillingCustomer>>(
        future: _customers,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return ListView(children: const [
              Padding(
                  padding: EdgeInsets.all(48),
                  child: Center(child: CircularProgressIndicator()))
            ]);
          }
          if (snapshot.hasError) {
            return ListView(children: [
              ListTile(
                  title: const Text('No se pudieron cargar los clientes.'),
                  trailing: TextButton(
                      onPressed: _reload, child: const Text('Reintentar')))
            ]);
          }
          final values = snapshot.data ?? const [];
          final terms = _terms(values);
          if (_selectedTerm != null && !terms.contains(_selectedTerm)) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _selectedTerm = null);
            });
          }
          final filtered = values.where(_matches).toList();
          return ListView.builder(
              padding: const EdgeInsets.all(16),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              itemCount: filtered.isEmpty ? 3 : filtered.length + 2,
              itemBuilder: (_, index) {
                if (index == 0) {
                  return const Padding(
                      padding: EdgeInsets.only(bottom: 16),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Clientes',
                                style: TextStyle(
                                    fontSize: 22, fontWeight: FontWeight.bold)),
                            SizedBox(height: 4),
                            Text(
                                'Configura los plazos de pago y administra la programación de cobros.')
                          ]));
                }
                if (index == 1) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Column(children: [
                      LayoutBuilder(builder: (context, box) {
                        final search = TextField(
                          key: const ValueKey('customer-search'),
                          controller: _searchController,
                          textInputAction: TextInputAction.search,
                          onChanged: (value) => setState(() => _query = value),
                          decoration: InputDecoration(
                            hintText: 'Buscar cliente o nombre comercial',
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: _query.isEmpty
                                ? null
                                : IconButton(
                                    tooltip: 'Limpiar búsqueda',
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() => _query = '');
                                    },
                                    icon: const Icon(Icons.close)),
                          ),
                        );
                        final term = DropdownButtonFormField<Object?>(
                          key: ValueKey('payment-term-filter-$_selectedTerm'),
                          initialValue: terms.contains(_selectedTerm)
                              ? _selectedTerm
                              : null,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Plazo de pago',
                            prefixIcon: Icon(Icons.filter_alt_outlined),
                          ),
                          items: <DropdownMenuItem<Object?>>[
                            const DropdownMenuItem(
                                value: null, child: Text('Todos los plazos')),
                            ...terms.map((value) => DropdownMenuItem<Object?>(
                                value: value,
                                child: Text(value == pendingTerm
                                    ? 'Pendiente'
                                    : '$value días'))),
                          ],
                          onChanged: (value) =>
                              setState(() => _selectedTerm = value),
                        );
                        if (box.maxWidth < 650) {
                          return Column(children: [
                            search,
                            const SizedBox(height: 10),
                            term,
                          ]);
                        }
                        return Row(children: [
                          Expanded(flex: 7, child: search),
                          const SizedBox(width: 12),
                          Expanded(flex: 3, child: term),
                        ]);
                      }),
                      if (_query.trim().isNotEmpty || _selectedTerm != null)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: _clearFilters,
                            icon: const Icon(Icons.filter_alt_off_outlined),
                            label: const Text('Limpiar filtros'),
                          ),
                        ),
                    ]),
                  );
                }
                if (values.isEmpty) {
                  return const _CustomersEmptyState(filtered: false);
                }
                if (filtered.isEmpty) {
                  return _CustomersEmptyState(
                      filtered: true, onClear: _clearFilters);
                }
                final c = filtered[index - 2];
                return _CustomerCard(
                    customer: c, onOpen: () => _openHistory(c));
              });
        },
      ));
}

class _CustomersEmptyState extends StatelessWidget {
  const _CustomersEmptyState({required this.filtered, this.onClear});
  final bool filtered;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 16),
        child: Column(children: [
          Icon(filtered ? Icons.search_off : Icons.groups_outlined, size: 44),
          const SizedBox(height: 12),
          Text(
              filtered
                  ? 'No se encontraron clientes'
                  : 'La organización todavía no tiene clientes',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Text(
              filtered
                  ? 'Prueba con otro nombre, nombre comercial o plazo de pago.'
                  : 'Los clientes aparecerán aquí cuando estén disponibles.',
              textAlign: TextAlign.center),
          if (filtered) ...[
            const SizedBox(height: 12),
            TextButton(
                onPressed: onClear, child: const Text('Limpiar filtros')),
          ],
        ]),
      );
}

class _PaymentTermDialog extends StatefulWidget {
  const _PaymentTermDialog({required this.customer});
  final BillingCustomer customer;
  @override
  State<_PaymentTermDialog> createState() => _PaymentTermDialogState();
}

class _PaymentTermDialogState extends State<_PaymentTermDialog> {
  late final TextEditingController controller = TextEditingController(
      text: widget.customer.paymentTermDays?.toString() ?? '');
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: Text(widget.customer.name),
          content: TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                  labelText: 'Plazo habitual en días',
                  helperText: 'Usa 0 para pago el mismo día.')),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: () {
                  final value = parsePaymentTerm(controller.text);
                  if (value != null) Navigator.pop(context, value);
                },
                child: const Text('Continuar'))
          ]);
}

class _OperationDialog extends StatefulWidget {
  const _OperationDialog(
      {required this.title,
      required this.body,
      required this.customer,
      required this.confirmLabel,
      required this.operation,
      this.destructive = false});
  final String title, body, confirmLabel;
  final BillingCustomer customer;
  final Future<void> Function() operation;
  final bool destructive;
  @override
  State<_OperationDialog> createState() => _OperationDialogState();
}

class _OperationDialogState extends State<_OperationDialog> {
  bool loading = false;
  String? error;
  Future<void> confirm() async {
    if (loading) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      await widget.operation();
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() {
          loading = false;
          error = 'No se pudo completar la operación. Inténtalo nuevamente.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: Text(widget.title),
          content: SingleChildScrollView(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                Text(widget.body),
                const SizedBox(height: 16),
                const Text('Cliente:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                Text(widget.customer.name),
                const SizedBox(height: 8),
                const Text('Nombre comercial:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                Text(widget.customer.commercialName.isEmpty
                    ? 'Sin nombre comercial'
                    : widget.customer.commercialName),
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(error!,
                      style:
                          TextStyle(color: Theme.of(context).colorScheme.error))
                ]
              ])),
          actions: [
            TextButton(
                autofocus: true,
                onPressed: loading ? null : () => Navigator.pop(context, false),
                child: const Text('Cancelar')),
            FilledButton(
                style: widget.destructive
                    ? FilledButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.error)
                    : null,
                onPressed: loading ? null : confirm,
                child: loading
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(widget.confirmLabel))
          ]);
}

class _CustomerCard extends StatelessWidget {
  const _CustomerCard({required this.customer, required this.onOpen});
  final BillingCustomer customer;
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext context) => Semantics(
      label:
          'Abrir historial de ${customer.name} – ${customer.commercialName.isEmpty ? 'Sin nombre comercial' : customer.commercialName}',
      button: true,
      child: Card(
          margin: const EdgeInsets.only(bottom: 8),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
              canRequestFocus: true,
              onTap: onOpen,
              child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: LayoutBuilder(builder: (_, box) {
                    final mobile = box.maxWidth < 620;
                    final name =
                        _CustomerField(label: 'Cliente', value: customer.name);
                    final commercial = _CustomerField(
                        label: 'Nombre comercial',
                        value: customer.commercialName.isEmpty
                            ? 'Sin nombre comercial'
                            : customer.commercialName);
                    final badge = _StatusBadge(customer: customer);
                    if (mobile) {
                      return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    name,
                                    const SizedBox(height: 8),
                                    Row(children: [
                                      Expanded(child: commercial),
                                      const Icon(Icons.chevron_right)
                                    ]),
                                  ]),
                            ),
                            Row(children: [
                              badge,
                              const Spacer(),
                              const Icon(Icons.chevron_right),
                            ]),
                          ]);
                    }
                    return Row(children: [
                      Expanded(
                          child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Row(children: [
                                Expanded(flex: 31, child: name),
                                const SizedBox(width: 14),
                                Expanded(flex: 29, child: commercial),
                                const SizedBox(width: 14),
                                Expanded(
                                    flex: 17,
                                    child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: badge)),
                                const Icon(Icons.chevron_right)
                              ]))),
                    ]);
                  })))));
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.customer});
  final BillingCustomer customer;
  @override
  Widget build(BuildContext context) {
    final color = customer.configured ? Colors.green : Colors.amber;
    final text =
        customer.configured ? '${customer.paymentTermDays} días' : 'Pendiente';
    return Semantics(
        label: 'Días configurados: $text',
        child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
                color: color.withValues(alpha: .16),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: color.withValues(alpha: .45))),
            child: Text(text,
                style: TextStyle(
                    color: color.shade200, fontWeight: FontWeight.w600))));
  }
}

class _CustomerField extends StatelessWidget {
  const _CustomerField({required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => Tooltip(
      message: value,
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 2),
            Text(value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600))
          ]));
}
