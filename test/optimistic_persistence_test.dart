import 'package:cosmeticos_hg_reportes/services/optimistic_persistence.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a remote failure reverts the optimistic state', () async {
    var visibleAsSaved = true;

    final saved = await persistirConReversion(
      persistir: () async => throw Exception('controlled RPC failure'),
      revertir: () async => visibleAsSaved = false,
    );

    expect(saved, isFalse);
    expect(visibleAsSaved, isFalse);
  });

  test('a confirmed remote write keeps the optimistic state', () async {
    var reverted = false;

    final saved = await persistirConReversion(
      persistir: () async {},
      revertir: () async => reverted = true,
    );

    expect(saved, isTrue);
    expect(reverted, isFalse);
  });
}
