import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:math';

import '../models/factura.dart';
import '../models/billing_customer.dart';
import '../models/payment_reminder.dart';
import '../services/firebase_messaging_service.dart';
import '../services/notification_diagnostics_repository.dart';
import '../services/notification_schedule.dart';
import '../services/customer_terms_repository.dart';
import '../services/payment_reminders_repository.dart';
import '../widgets/notification_permission_dialog.dart';

class PaymentRemindersScreen extends StatefulWidget {
  const PaymentRemindersScreen({
    this.initialFacturaId,
    this.repository,
    this.notificationDiagnostics,
    this.notificationStatusLoader,
    super.key,
  });
  final String? initialFacturaId;
  final PaymentRemindersDataSource? repository;
  final NotificationDiagnosticsDataSource? notificationDiagnostics;
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
  bool _notificationTestBusy = false;
  late final NotificationDiagnosticsDataSource _notificationDiagnostics =
      widget.notificationDiagnostics ?? NotificationDiagnosticsRepository();

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

  Future<void> _runNotificationTest() async {
    if (_notificationTestBusy) return;
    setState(() => _notificationTestBusy = true);
    try {
      final preview = await _notificationDiagnostics.previewAllMyDevices();
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Vista previa'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      'Dispositivos Android elegibles: ${preview.eligibleDevices}'),
                  Text('Dispositivos inactivos: ${preview.inactiveDevices}'),
                  Text(
                      'Tokens duplicados omitidos: ${preview.duplicatesOmitted}'),
                  const SizedBox(height: 12),
                  Text(
                      'Se enviará una notificación de prueba a ${preview.eligibleDevices} dispositivos. ¿Deseas continuar?'),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: preview.eligibleDevices == 0
                      ? null
                      : () => Navigator.pop(dialogContext, true),
                  child: const Text('Confirmar y enviar'),
                ),
              ],
            ),
          ) ??
          false;
      if (!confirmed || !mounted) return;
      final result = await _notificationDiagnostics
          .sendToAllMyDevices(preview.executionId);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Resultado de la prueba'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Dispositivos elegibles: ${result.eligibleDevices}'),
              Text('Envíos exitosos: ${result.successfulSends}'),
              Text('Tokens inválidos: ${result.invalidTokens}'),
              Text('Fallos: ${result.failures}'),
              Text('Duplicados omitidos: ${result.duplicatesOmitted}'),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      );
    } on FunctionException catch (error) {
      if (mounted) {
        final message = switch (error.status) {
          401 => 'La sesión expiró. Vuelve a iniciar sesión.',
          _ => 'No fue posible preparar la prueba (${error.status}).',
        };
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(message),
        ));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No fue posible preparar la prueba.'),
        ));
      }
    } finally {
      if (mounted) setState(() => _notificationTestBusy = false);
    }
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
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  alignment: WrapAlignment.end,
                  children: [
                    TextButton.icon(
                      onPressed:
                          _notificationTestBusy ? null : _runNotificationTest,
                      icon: _notificationTestBusy
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send_to_mobile_outlined),
                      label: const Text(
                          'Probar notificaciones en todos mis dispositivos'),
                    ),
                  ],
                ),
              ),
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
                                      'Cliente: ${_valueOrFallback(item.cliente)}\nNombre comercial: ${_valueOrFallback(item.nombreComercial)}\n${_format(item.paymentDate)} · ${item.active ? 'Activo' : 'Inactivo'}\nSe notifica únicamente ese mismo día'),
                                  isThreeLine: false,
                                  trailing: item.active
                                      ? IconButton(
                                          tooltip:
                                              'Agregar seguimiento / Reprogramar cobro',
                                          icon: const Icon(
                                              Icons.history_outlined),
                                          onPressed: () => _followup(item))
                                      : null,
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

  Future<void> _followup(PaymentReminder reminder) async {
    final invoice = await _repository.findInvoice(reminder.facturaId);
    if (!mounted || invoice == null) return;
    final changed = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => _FollowupEditor(
            invoice: invoice, reminder: reminder, repository: _repository));
    if (changed ?? false) await _reload();
  }

  static String _format(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  static String _valueOrFallback(String value) =>
      value.trim().isEmpty ? 'Sin registrar' : value.trim();
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
  final _termsRepository = CustomerTermsRepository();
  late DateTime _date = widget.reminder?.paymentDate ?? DateTime.now();
  late bool _active = widget.reminder?.active ?? true;
  bool _saving = false;

  Future<void> _configureInvoiceTerm() async {
    final plan =
        await _termsRepository.getInvoicePlan(widget.invoice.secuencial);
    if (!mounted) return;
    if (plan == null || plan.invoiceDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Plazo pendiente de configurar para esta factura.')));
      return;
    }
    var useException = plan.exceptionalTermDays != null;
    final controller =
        TextEditingController(text: plan.exceptionalTermDays?.toString() ?? '');
    final selected = await showDialog<int?>(
        context: context,
        builder: (context) => StatefulBuilder(builder: (context, update) {
              final parsed = parsePaymentTerm(controller.text);
              final days = useException ? parsed : plan.customerTermDays;
              final calculated = days == null
                  ? null
                  : calculatePaymentDate(plan.invoiceDate!, days);
              return AlertDialog(
                title: const Text('Plazo de esta factura'),
                content: Column(mainAxisSize: MainAxisSize.min, children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Fecha de factura'),
                    trailing: Text(PaymentRemindersScreenStateHelper.format(
                        plan.invoiceDate!)),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Plazo habitual'),
                    trailing: Text(plan.customerTermDays == null
                        ? 'Pendiente'
                        : '${plan.customerTermDays} días'),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: useException,
                    onChanged: (value) =>
                        update(() => useException = value ?? false),
                    title:
                        const Text('Usar un plazo diferente para esta factura'),
                  ),
                  if (useException)
                    TextField(
                      controller: controller,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      onChanged: (_) => update(() {}),
                      decoration: const InputDecoration(
                          labelText: 'Días excepcionales'),
                    ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(calculated == null
                        ? 'Plazo pendiente de configurar'
                        : 'Fecha definitiva: ${PaymentRemindersScreenStateHelper.format(calculated)}'),
                  ),
                ]),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancelar')),
                  FilledButton(
                      onPressed: days == null
                          ? null
                          : () => Navigator.pop(
                              context, useException ? parsed : -1),
                      child: const Text('Guardar')),
                ],
              );
            }));
    controller.dispose();
    if (selected == null || !mounted) return;
    final exception = selected == -1 ? null : selected;
    final calculatedDays = exception ?? plan.customerTermDays;
    final proposed = calculatedDays == null
        ? null
        : calculatePaymentDate(plan.invoiceDate!, calculatedDays);
    var confirmManual = false;
    if (plan.manualSchedule && proposed != plan.currentPaymentDate) {
      confirmManual = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                    title: const Text('Programación manual existente'),
                    content: Text(
                        'Fecha manual: ${plan.currentPaymentDate == null ? 'Sin fecha' : PaymentRemindersScreenStateHelper.format(plan.currentPaymentDate!)}\nFecha calculada: ${proposed == null ? 'Sin fecha' : PaymentRemindersScreenStateHelper.format(proposed)}\n¿Deseas reemplazarla?'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Conservar manual')),
                      FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Reemplazar')),
                    ],
                  )) ??
          false;
      if (!confirmManual) return;
    }
    final effective = await _termsRepository.saveInvoiceException(
        widget.invoice.secuencial, exception,
        confirmManualOverride: confirmManual);
    if (!mounted) return;
    if (effective != null) setState(() => _date = effective);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Plazo de la factura guardado correctamente.')));
  }

  Future<void> _pickDate() async {
    final selected = await showDatePicker(
        context: context,
        initialDate: _date,
        firstDate: DateTime.now(),
        lastDate: DateTime.now().add(const Duration(days: 3650)));
    if (selected != null) {
      final effective = effectiveBusinessDate(selected);
      setState(() => _date = effective);
      if (effective != selected && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'La fecha seleccionada cae en fin de semana. El cobro fue programado para el lunes ${PaymentRemindersScreenStateHelper.format(effective)}.')));
      }
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.repository.save(
          facturaId: widget.invoice.secuencial,
          paymentDate: _date,
          active: _active,
          notifyThreeDays: true,
          notifyOneDay: true);
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
            onTap: widget.reminder == null ? _pickDate : null),
        OutlinedButton.icon(
            onPressed: _saving ? null : _configureInvoiceTerm,
            icon: const Icon(Icons.calendar_month_outlined),
            label: const Text('Usar plazo habitual o excepcional')),
        if (widget.reminder != null)
          const Text(
              'Para cambiar la fecha usa “Agregar seguimiento / Reprogramar cobro” desde la lista.'),
        SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Recordatorio activo'),
            value: _active,
            onChanged: (value) => setState(() => _active = value)),
        const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.notifications_active_outlined),
            title: Text('Notificación el mismo día'),
            subtitle: Text(
                'Hora de envío: ${NotificationSchedule.localTime} · Zona horaria: ${NotificationSchedule.timeZoneLabel}')),
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

class _FollowupEditor extends StatefulWidget {
  const _FollowupEditor(
      {required this.invoice,
      required this.reminder,
      required this.repository});
  final Factura invoice;
  final PaymentReminder reminder;
  final PaymentRemindersDataSource repository;
  @override
  State<_FollowupEditor> createState() => _FollowupEditorState();
}

class _FollowupEditorState extends State<_FollowupEditor> {
  final _comment = TextEditingController();
  DateTime? _requestedDate;
  bool _saving = false;
  late final String _idempotencyKey = _newRequestId();
  late final Future<List<PaymentFollowup>> _history =
      widget.repository.listFollowups(widget.reminder.id);

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final selected = await showDatePicker(
        context: context,
        initialDate: _requestedDate ?? widget.reminder.paymentDate,
        firstDate: DateTime.now(),
        lastDate: DateTime.now().add(const Duration(days: 3650)));
    if (selected != null) setState(() => _requestedDate = selected);
  }

  Future<void> _save() async {
    if (_comment.text.trim().isEmpty && _requestedDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Ingresa un comentario o selecciona una fecha.')));
      return;
    }
    setState(() => _saving = true);
    try {
      final result = await widget.repository.addFollowup(
          reminderId: widget.reminder.id,
          requestId: _idempotencyKey,
          comment: _comment.text,
          requestedPaymentDate: _requestedDate);
      if (!mounted) return;
      final message = result.rescheduled
          ? 'Cobro actualizado y recordatorios reprogramados para el ${PaymentRemindersScreenStateHelper.format(result.effectivePaymentDate)}.'
          : 'Seguimiento registrado correctamente.';
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('No se pudo registrar el seguimiento.')));
      }
    }
  }

  String _newRequestId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  @override
  Widget build(BuildContext context) {
    final effective = _requestedDate == null
        ? widget.reminder.paymentDate
        : effectiveBusinessDate(_requestedDate!);
    final adjusted = _requestedDate != null && effective != _requestedDate;
    return Padding(
        padding: EdgeInsets.fromLTRB(
            20, 20, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
        child: SingleChildScrollView(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
              Text('Agregar seguimiento / Reprogramar cobro',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              Text(
                  'Factura ${widget.invoice.secuencial} · ${widget.invoice.nombreComercial.isEmpty ? widget.invoice.cliente : widget.invoice.nombreComercial}'),
              Text(
                  'Fecha actual: ${PaymentRemindersScreenStateHelper.format(widget.reminder.paymentDate)}'),
              const SizedBox(height: 16),
              TextField(
                  controller: _comment,
                  maxLength: 4000,
                  maxLines: 3,
                  decoration: const InputDecoration(
                      labelText: 'Comentario', border: OutlineInputBorder())),
              ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Nueva fecha de cobro (opcional)'),
                  subtitle: Text(_requestedDate == null
                      ? 'Sin cambio de fecha'
                      : PaymentRemindersScreenStateHelper.format(
                          _requestedDate!)),
                  trailing: const Icon(Icons.edit_calendar_outlined),
                  onTap: _saving ? null : _pickDate),
              if (_requestedDate != null) ...[
                Text(
                    'Fecha definitiva: ${PaymentRemindersScreenStateHelper.format(effective)}'),
                if (adjusted)
                  Text(
                      'La fecha seleccionada cae en fin de semana. El cobro fue programado para el lunes ${PaymentRemindersScreenStateHelper.format(effective)}.'),
                TextButton(
                    onPressed: _saving
                        ? null
                        : () => setState(() => _requestedDate = null),
                    child: const Text('Quitar cambio de fecha')),
              ],
              Row(children: [
                Expanded(
                    child: OutlinedButton(
                        onPressed: _saving
                            ? null
                            : () => Navigator.pop(context, false),
                        child: const Text('Cancelar'))),
                const SizedBox(width: 12),
                Expanded(
                    child: FilledButton(
                        onPressed: _saving ? null : _save,
                        child: Text(_saving ? 'Guardando…' : 'Guardar'))),
              ]),
              const SizedBox(height: 24),
              Text('Historial de seguimientos y reprogramaciones',
                  style: Theme.of(context).textTheme.titleMedium),
              FutureBuilder<List<PaymentFollowup>>(
                  future: _history,
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final items = snapshot.data!;
                    if (items.isEmpty) {
                      return const Padding(
                          padding: EdgeInsets.all(12),
                          child: Text('Sin seguimientos registrados.'));
                    }
                    return Column(
                        children: items
                            .map((item) => _FollowupTile(item: item))
                            .toList());
                  }),
            ])));
  }
}

class _FollowupTile extends StatelessWidget {
  const _FollowupTile({required this.item});
  final PaymentFollowup item;
  @override
  Widget build(BuildContext context) {
    final details = <String>[
      _actionLabel(item.actionType),
      if (item.previousPaymentDate != null)
        'Anterior: ${PaymentRemindersScreenStateHelper.format(item.previousPaymentDate!)}',
      if (item.requestedPaymentDate != null)
        'Solicitada: ${PaymentRemindersScreenStateHelper.format(item.requestedPaymentDate!)}',
      if (item.effectivePaymentDate != null)
        'Programada: ${PaymentRemindersScreenStateHelper.format(item.effectivePaymentDate!)}',
      'Usuario: ${item.createdBy ?? 'No disponible'}',
    ];
    return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.history),
        title: Text(item.comment ?? _actionLabel(item.actionType)),
        subtitle: Text('${_dateTime(item.createdAt)}\n${details.join(' · ')}'));
  }

  static String _actionLabel(String value) => switch (value) {
        'comment' => 'Comentario',
        'reschedule' => 'Reprogramación',
        _ => 'Comentario y reprogramación',
      };
  static String _dateTime(DateTime value) =>
      '${PaymentRemindersScreenStateHelper.format(value.toLocal())} ${value.toLocal().hour.toString().padLeft(2, '0')}:${value.toLocal().minute.toString().padLeft(2, '0')}';
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
