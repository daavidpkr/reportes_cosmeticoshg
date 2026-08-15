import 'package:flutter/material.dart';

import '../../../models/payment_calendar_entry.dart';
import '../../../models/payment_calendar_rules.dart';
import 'calendar_day_cell.dart';

class CalendarGrid extends StatelessWidget {
  const CalendarGrid(
      {required this.month,
      required this.grouped,
      required this.selected,
      required this.onSelect,
      super.key});
  final DateTime month;
  final Map<DateTime, List<PaymentCalendarEntry>> grouped;
  final DateTime? selected;
  final ValueChanged<DateTime> onSelect;

  bool _same(DateTime? a, DateTime b) =>
      a != null && a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final compact = constraints.maxWidth < 900;
        final days = mondayFirstCalendarDays(month);
        final rows = days.length ~/ 7;
        const rowSpacing = 4.0;
        final rowHeight = compact ? 62.0 : 112.0;
        final height = rows * rowHeight + (rows - 1) * rowSpacing;
        final labels = compact
            ? const ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom']
            : const [
                'Lunes',
                'Martes',
                'Miércoles',
                'Jueves',
                'Viernes',
                'Sábado',
                'Domingo'
              ];
        return Column(children: [
          Row(children: [
            for (final label in labels)
              Expanded(
                  child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(label,
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .labelMedium
                              ?.copyWith(fontWeight: FontWeight.w700))))
          ]),
          SizedBox(
              height: height,
              child: GridView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: days.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 7,
                      mainAxisExtent: rowHeight,
                      crossAxisSpacing: 4,
                      mainAxisSpacing: rowSpacing),
                  itemBuilder: (_, index) {
                    final day = days[index];
                    return CalendarDayCell(
                        day: day,
                        entries: grouped[dateOnly(day)] ?? const [],
                        currentMonth: day.month == month.month,
                        today: _same(DateTime.now(), day),
                        selected: _same(selected, day),
                        compact: compact,
                        onTap: () => onSelect(day));
                  })),
        ]);
      });
}
