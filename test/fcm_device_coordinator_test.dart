import 'package:cosmeticos_hg_reportes/services/fcm_device_repository.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeDevices implements FcmDeviceDataSource {
  final registered = <String>[];
  final deactivated = <String>[];
  int failures = 0;
  @override
  Future<void> register(String token) async {
    if (failures-- > 0) throw Exception('temporary');
    registered.add(token);
  }

  @override
  Future<void> deactivate(String token) async => deactivated.add(token);
}

void main() {
  test('retiene el token hasta que exista sesión', () async {
    final fake = FakeDevices();
    final coordinator = FcmDeviceCoordinator(repository: fake);
    await coordinator.onTokenChanged('token-inicial-suficientemente-largo');
    expect(fake.registered, isEmpty);
    await coordinator.onSignedIn();
    expect(fake.registered, ['token-inicial-suficientemente-largo']);
    coordinator.dispose();
  });
  test('registra una renovación sin duplicar el mismo token', () async {
    final fake = FakeDevices();
    final coordinator = FcmDeviceCoordinator(repository: fake);
    await coordinator.onSignedIn();
    await coordinator.onTokenChanged('token-uno-suficientemente-largo');
    await coordinator.onTokenChanged('token-uno-suficientemente-largo');
    await coordinator.onTokenChanged('token-dos-suficientemente-largo');
    expect(fake.registered,
        ['token-uno-suficientemente-largo', 'token-dos-suficientemente-largo']);
    expect(fake.deactivated, ['token-uno-suficientemente-largo']);
    coordinator.dispose();
  });
  test('desactiva únicamente el token actual al cerrar sesión', () async {
    final fake = FakeDevices();
    final coordinator = FcmDeviceCoordinator(repository: fake);
    await coordinator.onSignedIn();
    await coordinator.onTokenChanged('token-actual-suficientemente-largo');
    await coordinator.onSignedOut();
    expect(fake.deactivated, ['token-actual-suficientemente-largo']);
    coordinator.dispose();
  });
  test('reintenta un error temporal sin bloquear', () async {
    final fake = FakeDevices()..failures = 1;
    final coordinator = FcmDeviceCoordinator(
        repository: fake, retryDelay: const Duration(milliseconds: 5));
    await coordinator.onSignedIn();
    await coordinator.onTokenChanged('token-reintento-suficientemente-largo');
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(fake.registered, ['token-reintento-suficientemente-largo']);
    coordinator.dispose();
  });
}
