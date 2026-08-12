Future<bool> persistirConReversion({
  required Future<void> Function() persistir,
  required Future<void> Function() revertir,
}) async {
  try {
    await persistir();
    return true;
  } catch (_) {
    await revertir();
    return false;
  }
}
