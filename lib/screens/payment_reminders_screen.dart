import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import '../models/factura.dart';
import '../models/payment_reminder.dart';
import '../services/firebase_messaging_service.dart';
import '../services/payment_reminders_repository.dart';
import '../widgets/notification_permission_dialog.dart';

class PaymentRemindersScreen extends StatefulWidget {
  const PaymentRemindersScreen({
    this.initialFacturaId,
    this.repository,
    this.notificationStatusLoader,
    super.key,
  });
  final String? initialFacturaId;
  final PaymentRemindersDataSource? repository;
  final Future<AuthorizationStatus> Function()? notificationStatusLoader;

  @override
  State<PaymentRemindersScreen> createState() => _PaymentRemindersScreenState();
}

class _PaymentRemindersScreenState extends State<PaymentRemindersScreen> {
  late final PaymentRemindersDataSource _repository =
      widget.repository ?? PaymentRemindersRepository();
  late Future<List<PaymentReminder>> _reminders;
  AuthorizationStatus? _permission;
  bool _handledInitial = false;

  @override
  void initState() {
    super.initState();
    _reminders = _repository.list();
    _loadPermission();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_handledInitial && widget.initialFacturaId != null) {
      _handledInitial = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _openInitial());
    }
  }

  Future<void> _loadPermission() async {
    final status = await (widget.notificationStatusLoader?.call() ??
        FirebaseMessagingService.instance.authorizationStatus());
    if (mounted) setState(() => _permission = status);
  }

  Future<void> _openInitial() async {
    final invoice = await _repository.findInvoice(widget.initialFacturaId!);
    if (!mounted) return;
    if (invoice == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('La factura ya no existe o no está disponible.')));
      return;
    }
    await _edit(invoice);
  }

  Future<void> _reload() async {
    final value = _repository.list();
    setState(() => _reminders = value);
    await value;
  }

  Future<void> _chooseInvoice() async {
    final invoices = await _repository.listInvoices();
    if (!mounted) return;
    final selected = await showSearch<Factura?>(
        context: context, delegate: _InvoiceSearch(invoices));
    if (selected != null && mounted) await _edit(selected);
  }

  Future<void> _edit(Factura invoice, [PaymentReminder? existing]) async {
    existing ??= await _repository.findForInvoice(invoice.secuencial);
    if (!mounted) return;
    final changed = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => _ReminderEditor(
            invoice: invoice, reminder: existing, repository: _repository));
    if (changed ?? false) await _reload();
  }

  bool get _disabled => _permission == AuthorizationStatus.denied;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Recordatorios de pago')),
        floatingActionButton: FloatingActionButton.extended(
            onPressed: _chooseInvoice,
            icon: const Icon(Icons.add_alert_outlined),
            label: const Text('Programar')),
        body: RefreshIndicator(
            onRefresh: _reload,
            child: ListView(padding: const EdgeInsets.all(16), children: [
              Card(
                  child: ListTile(
                leading: Icon(_disabled
                    ? Icons.notifications_off_outlined
                    : Icons.notifications_active_outlined),
                title: Text(_disabled
                    ? 'Notificaciones desactivadas'
                    : 'Avisos de Android'),
                subtitle: Text(_disabled
                    ? 'Tus fechas se guardan, pero Android no mostrará avisos.'
                    : 'Activa los avisos para recibir recordatorios en este dispositivo.'),
                trailing: TextButton(
                    onPressed: () async {
                      await requestNotificationPermissionWithExplanation(
                          context);
                      await _loadPermission();
                    },
                    child: Text(_disabled ? 'Configurar' : 'Activar')),
              )),
              const SizedBox(height: 8),
              FutureBuilder<List<PaymentReminder>>(
                  future: _reminders,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Padding(
                          padding: EdgeInsets.all(32),
                          child: Center(child: CircularProgressIndicator()));
                    }
                    if (snapshot.hasError) return _ErrorCard(onRetry: _reload);
                    final values = snapshot.data ?? const [];
                    if (values.isEmpty) {
                      return const Card(
                          child: Padding(
                              padding: EdgeInsets.all(28),
                              child: Text(
                                  'No tienes pagos programados. Usa “Programar” para escoger una factura.',
                                  textAlign: TextAlign.center)));
                    }
                    return Column(
                        children: values
                            .map((item) => Card(
                                    child: ListTile(
                                  leading: Icon(item.active
                                      ? Icons.event_available_outlined
                                      : Icons.event_busy_outlined),
                                  title: Text('Factura ${item.facturaId}'),
                                  subtitle: Text(
                                      '${_format(item.paymentDate)} · ${item.active ? 'Activo' : 'Inactivo'}\n${_notices(item)}'),
                                  isThreeLine: true,
                                  onTap: () async {
                                    final invoice = await _repository
                                        .findInvoice(item.facturaId);
                                    if (invoice != null && mounted) {
                                      await _edit(invoice, item);
                                    }
                                  },
                                )))
                            .toList());
                  }),
              const SizedBox(height: 80),
            ])),
      );

  static String _format(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  static String _notices(PaymentReminder item) => [
        if (item.notifyThreeDays) '3 días antes',
        if (item.notifyOneDay) '1 día antes'
      ].join(' y ');
}

class _ReminderEditor extends StatefulWidget {
  const _ReminderEditor(
      {required this.invoice,
      required this.reminder,
      required this.repository});
  final Factura invoice;
  final PaymentReminder? reminder;
  final PaymentRemindersDataSource repository;
  @override
  State<_ReminderEditor> createState() => _ReminderEditorState();
}

class _ReminderEditorState extends State<_ReminderEditor> {
  late DateTime _date = widget.reminder?.paymentDate ??
      DateTime.now().add(const Duration(days: 3));
  late bool _active = widget.reminder?.active ?? true;
  late bool _three = widget.reminder?.notifyThreeDays ?? true;
  late bool _one = widget.reminder?.notifyOneDay ?? true;
  bool _saving = false;

  Future<void> _pickDate() async {
    final selected = await showDatePicker(
        context: context,
        initialDate: _date,
        firstDate: DateTime.now(),
        lastDate: DateTime.now().add(const Duration(days: 3650)));
    if (selected != null) setState(() => _date = selected);
  }

  Future<void> _save() async {
    if (!_three && !_one) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Activa al menos un aviso.')));
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.repository.save(
          facturaId: widget.invoice.secuencial,
          paymentDate: _date,
          active: _active,
          notifyThreeDays: _three,
          notifyOneDay: _one);
      if (!mounted) return;
      await requestNotificationPermissionWithExplanation(context);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'No se pudo guardar el recordatorio. Revisa la conexión.')));
      }
    }
  }

  Future<void> _delete() async {
    final id = widget.reminder?.id;
    if (id == null) return;
    setState(() => _saving = true);
    try {
      await widget.repository.delete(id);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
      child: SingleChildScrollView(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Factura ${widget.invoice.secuencial}',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(widget.invoice.nombreComercial.isEmpty
            ? widget.invoice.cliente
            : widget.invoice.nombreComercial),
        const SizedBox(height: 20),
        ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.calendar_today_outlined),
            title: const Text('Fecha de pago'),
            subtitle: Text(PaymentRemindersScreenStateHelper.format(_date)),
            trailing: const Icon(Icons.edit_calendar_outlined),
            onTap: _pickDate),
        SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Recordatorio activo'),
            value: _active,
            onChanged: (value) => setState(() => _active = value)),
        CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Avisar 3 días antes'),
            value: _three,
            onChanged: (value) => setState(() => _three = value ?? false)),
        CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Avisar 1 día antes'),
            value: _one,
            onChanged: (value) => setState(() => _one = value ?? false)),
        const SizedBox(height: 12),
        FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.save_outlined),
            label: Text(_saving ? 'Guardando…' : 'Guardar')),
        if (widget.reminder != null)
          TextButton.icon(
              onPressed: _saving ? null : _delete,
              icon: const Icon(Icons.delete_outline),
              label: const Text('Eliminar recordatorio')),
      ])));
}

class PaymentRemindersScreenStateHelper {
  static String format(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}

class _InvoiceSearch extends SearchDelegate<Factura?> {
  _InvoiceSearch(this.invoices);
  final List<Factura> invoices;
  @override
  List<Widget>? buildActions(BuildContext context) =>
      [IconButton(onPressed: () => query = '', icon: const Icon(Icons.clear))];
  @override
  Widget? buildLeading(BuildContext context) => IconButton(
      onPressed: () => close(context, null),
      icon: const Icon(Icons.arrow_back));
  @override
  Widget buildResults(BuildContext context) => _results(context);
  @override
  Widget buildSuggestions(BuildContext context) => _results(context);
  Widget _results(BuildContext context) {
    final value = query.trim().toLowerCase();
    final matches = invoices
        .where((item) =>
            value.isEmpty ||
            item.secuencial.toLowerCase().contains(value) ||
            item.cliente.toLowerCase().contains(value) ||
            item.nombreComercial.toLowerCase().contains(value))
        .take(100);
    return ListView(
        children: matches
            .map((item) => ListTile(
                title: Text('Factura ${item.secuencial}'),
                subtitle: Text(item.nombreComercial.isEmpty
                    ? item.cliente
                    : item.nombreComercial),
                onTap: () => close(context, item)))
            .toList());
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.onRetry});
  final Future<void> Function() onRetry;
  @override
  Widget build(BuildContext context) => Card(
      child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(children: [
            const Text('No se pudieron cargar los recordatorios.'),
            TextButton(onPressed: onRetry, child: const Text('Reintentar'))
          ])));
}
