import 'package:flutter/material.dart';

import '../theme/hg_theme.dart';
import 'fila_venta.dart';

enum InvoiceStatus { pending, partial, overdue, paid, cancelled }

DateTime? invoiceDueDate(FilaVenta invoice, {DateTime? scheduledDate}) {
  if (scheduledDate != null) return DateUtils.dateOnly(scheduledDate);
  final term = invoice.paymentTermDays;
  if (term == null) return null;
  final raw = invoice.fecha.trim();
  DateTime? issued = DateTime.tryParse(raw);
  if (issued == null) {
    final parts = raw.split(RegExp(r'[/\-]'));
    if (parts.length == 3) {
      final first = int.tryParse(parts[0]);
      final month = int.tryParse(parts[1]);
      final last = int.tryParse(parts[2]);
      if (first != null && month != null && last != null) {
        issued = parts[0].length == 4
            ? DateTime(first, month, last)
            : DateTime(last, month, first);
      }
    }
  }
  return issued == null
      ? null
      : DateUtils.dateOnly(issued.add(Duration(days: term)));
}

InvoiceStatus invoiceStatus(
  FilaVenta invoice, {
  DateTime? scheduledDate,
  bool? overdue,
  DateTime? now,
}) {
  return invoiceStatusFromValues(
    cancelled: invoice.anulada,
    paid: invoice.pagada,
    balance: invoice.saldo,
    hasPayments: invoice.abonoParcial,
    dueDate: invoiceDueDate(invoice, scheduledDate: scheduledDate),
    overdue: overdue,
    now: now,
  );
}

InvoiceStatus invoiceStatusFromValues({
  required bool cancelled,
  required bool paid,
  required double balance,
  required bool hasPayments,
  DateTime? dueDate,
  bool? overdue,
  DateTime? now,
}) {
  if (cancelled) return InvoiceStatus.cancelled;
  if (paid) return InvoiceStatus.paid;
  final today = DateUtils.dateOnly(now ?? DateTime.now());
  if (balance > .005 && (overdue ?? (dueDate?.isBefore(today) == true))) {
    return InvoiceStatus.overdue;
  }
  return hasPayments ? InvoiceStatus.partial : InvoiceStatus.pending;
}

String invoiceStatusLabel(InvoiceStatus status) => switch (status) {
      InvoiceStatus.cancelled => 'Anulada',
      InvoiceStatus.paid => 'Pagada',
      InvoiceStatus.overdue => 'Atrasada',
      InvoiceStatus.partial => 'Abonada',
      InvoiceStatus.pending => 'Pendiente',
    };

Color invoiceStatusForeground(BuildContext context, InvoiceStatus status) {
  final colors = context.hg;
  return switch (status) {
    InvoiceStatus.cancelled => colors.danger,
    InvoiceStatus.paid => colors.positive,
    InvoiceStatus.overdue => const Color(0xFF168CFF),
    InvoiceStatus.partial || InvoiceStatus.pending => colors.warning,
  };
}

Color invoiceStatusBorder(Brightness brightness, InvoiceStatus status) =>
    switch (status) {
      InvoiceStatus.cancelled => const Color(0xFFFF1744),
      InvoiceStatus.paid => const Color(0xFF00E676),
      InvoiceStatus.overdue => const Color(0xFF00B7FF),
      InvoiceStatus.partial ||
      InvoiceStatus.pending =>
        brightness == Brightness.dark
            ? const Color(0xFFFFFF00)
            : const Color(0xFFFFC400),
    };

Color invoiceStatusBackground(BuildContext context, InvoiceStatus status) {
  final alpha = Theme.of(context).brightness == Brightness.dark ? .28 : .24;
  return invoiceStatusForeground(context, status).withValues(alpha: alpha);
}
