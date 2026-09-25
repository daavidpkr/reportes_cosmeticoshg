import 'package:cosmeticos_hg_reportes/services/document_download_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/document_downloads');

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('Android confirms the real name selected for a duplicate', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'saveDocument');
      expect(call.arguments['fileName'], 'reporte.pdf');
      expect(call.arguments['mimeType'], 'application/pdf');
      expect(call.arguments['bytes'], Uint8List.fromList([1, 2, 3]));
      return {
        'name': 'reporte (1).pdf',
        'location': 'Descargas/reporte (1).pdf',
      };
    });
    final service = DocumentDownloadService(
      androidChannel: channel,
      platformOverride: TargetPlatform.android,
    );

    final saved = await service.save(
      bytes: Uint8List.fromList([1, 2, 3]),
      fileName: 'reporte.pdf',
      mimeType: 'application/pdf',
    );

    expect(saved.name, 'reporte (1).pdf');
    expect(saved.location, 'Descargas/reporte (1).pdf');
  });

  test('Android propagates a useful write failure without confirming',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(
        code: 'document_write_failed',
        message: 'No se pudo escribir el archivo en Descargas: sin espacio.',
      );
    });
    final service = DocumentDownloadService(
      androidChannel: channel,
      platformOverride: TargetPlatform.android,
    );

    await expectLater(
      service.save(
        bytes: Uint8List.fromList([1]),
        fileName: 'reporte.pdf',
        mimeType: 'application/pdf',
      ),
      throwsA(
        isA<PlatformException>().having(
          (error) => error.message,
          'message',
          contains('sin espacio'),
        ),
      ),
    );
  });
}
