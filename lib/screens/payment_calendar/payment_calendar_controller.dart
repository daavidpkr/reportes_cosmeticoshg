import 'package:flutter/foundation.dart';

import '../../models/payment_calendar_entry.dart';
import '../../models/payment_calendar_rules.dart';
import '../../services/payment_calendar_repository.dart';

class PaymentCalendarController extends ChangeNotifier {
  PaymentCalendarController({required this.repository, DateTime? initialMonth})
      : visibleMonth = DateTime((initialMonth ?? DateTime.now()).year,
            (initialMonth ?? DateTime.now()).month);

  final PaymentCalendarDataSource repository;
  DateTime visibleMonth;
  DateTime? selectedDay;
  bool loading = false;
  String? error;
  List<PaymentCalendarEntry> entries = const [];
  final Map<String, List<PaymentCalendarEntry>> _cache = {};

  Map<DateTime, List<PaymentCalendarEntry>> get grouped =>
      entriesByDay(entries);
  String get _key => '${visibleMonth.year}-${visibleMonth.month}';

  Future<void> load({bool refresh = false}) async {
    if (loading) return;
    if (!refresh && _cache.containsKey(_key)) {
      entries = _cache[_key]!;
      error = null;
      notifyListeners();
      return;
    }
    loading = true;
    error = null;
    notifyListeners();
    try {
      entries = await repository.listMonth(visibleMonth);
      _cache[_key] = entries;
    } catch (_) {
      error = 'No fue posible cargar el calendario. Inténtalo nuevamente.';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> moveMonth(int offset) async {
    visibleMonth = DateTime(visibleMonth.year, visibleMonth.month + offset);
    selectedDay = null;
    await load();
  }

  Future<void> today() async {
    final now = DateTime.now();
    visibleMonth = DateTime(now.year, now.month);
    selectedDay = dateOnly(now);
    await load();
  }

  void select(DateTime day) {
    selectedDay = dateOnly(day);
    notifyListeners();
  }

  Future<bool> update(
      PaymentCalendarEntry entry, DateTime date, String comment) async {
    try {
      final saved = await repository.updateReminder(
          entry: entry, reminderDate: date, comment: comment);
      _cache.clear();
      entries =
          entries.where((item) => item.reminderId != entry.reminderId).toList();
      if (saved.reminderDate.year == visibleMonth.year &&
          saved.reminderDate.month == visibleMonth.month) {
        entries = [...entries, saved];
      }
      _cache[_key] = entries;
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }
}
