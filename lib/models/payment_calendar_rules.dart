import 'payment_calendar_entry.dart';
import 'payment_reminder.dart';

DateTime dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

DateTime adjustedReminderDate(DateTime value) => effectiveBusinessDate(value);

List<DateTime> mondayFirstCalendarDays(DateTime month) {
  final first = DateTime(month.year, month.month);
  final start = first.subtract(Duration(days: first.weekday - 1));
  final last = DateTime(month.year, month.month + 1, 0);
  final end = last.add(Duration(days: DateTime.sunday - last.weekday));
  return [
    for (var day = start;
        !day.isAfter(end);
        day = day.add(const Duration(days: 1)))
      day,
  ];
}

Map<DateTime, List<PaymentCalendarEntry>> entriesByDay(
    Iterable<PaymentCalendarEntry> entries) {
  final result = <DateTime, List<PaymentCalendarEntry>>{};
  final seen = <String>{};
  for (final entry in entries) {
    final key = '${entry.reminderId}:${dateOnly(entry.reminderDate)}';
    if (!seen.add(key)) continue;
    result.putIfAbsent(dateOnly(entry.reminderDate), () => []).add(entry);
  }
  return result;
}
