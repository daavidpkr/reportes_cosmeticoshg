import 'package:flutter/material.dart';

import '../../../models/payment_calendar_entry.dart';

class CalendarDayCell extends StatelessWidget {
  const CalendarDayCell({
    required this.day,
    required this.entries,
    required this.currentMonth,
    required this.today,
    required this.selected,
    required this.compact,
    required this.onTap,
    super.key,
  });
  final DateTime day;
  final List<PaymentCalendarEntry> entries;
  final bool currentMonth;
  final bool today;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final weekend = day.weekday >= DateTime.saturday;
    return Semantics(
      button: true,
      label: '${day.day}, ${entries.length} facturas pendientes',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: EdgeInsets.all(compact ? 4 : 8),
          decoration: BoxDecoration(
            color: selected
                ? colors.primaryContainer
                : weekend
                    ? colors.surfaceContainerHighest.withValues(alpha: .45)
                    : colors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: today ? colors.primary : colors.outlineVariant,
                width: today ? 2 : 1),
          ),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              height: 22,
              child: Stack(children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('${day.day}',
                      style: TextStyle(
                          fontSize: compact ? 12 : null,
                          fontWeight: today ? FontWeight.w800 : FontWeight.w600,
                          color: currentMonth
                              ? colors.onSurface
                              : colors.onSurfaceVariant.withValues(alpha: .5))),
                ),
                if (entries.isNotEmpty)
                  Align(
                    alignment: Alignment.centerRight,
                    child: Container(
                      constraints: BoxConstraints(minWidth: compact ? 18 : 22),
                      padding: EdgeInsets.symmetric(
                          horizontal: compact ? 4 : 6, vertical: 2),
                      decoration: BoxDecoration(
                          color: colors.primary,
                          borderRadius: BorderRadius.circular(20)),
                      child: Text('${entries.length}',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: colors.onPrimary,
                              fontSize: compact ? 10 : 11,
                              fontWeight: FontWeight.bold)),
                    ),
                  ),
              ]),
            ),
            if (!compact && entries.isNotEmpty) ...[
              const SizedBox(height: 5),
              Text(
                  '${entries.length} ${entries.length == 1 ? 'factura' : 'facturas'}',
                  style: Theme.of(context).textTheme.labelSmall),
              for (final entry in entries.take(2))
                Text('${entry.facturaId} · ${entry.cliente}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall),
              if (entries.length > 2)
                Text('+${entries.length - 2}',
                    style: TextStyle(
                        color: colors.primary, fontWeight: FontWeight.bold)),
            ],
          ]),
        ),
      ),
    );
  }
}
