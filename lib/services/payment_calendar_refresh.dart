import 'package:flutter/foundation.dart';

/// Invalidates calendar caches after a reminder changes outside the calendar.
class PaymentCalendarRefresh extends ChangeNotifier {
  void refresh() => notifyListeners();
}

final paymentCalendarRefresh = PaymentCalendarRefresh();
