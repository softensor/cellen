import 'package:cellen/core/api/api_client.dart';
import 'package:cellen/features/platform/schools/school_config_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class _SchoolApi extends ApiClient {
  _SchoolApi() : super(const FlutterSecureStorage());
  Map<String, dynamic> features = {'external_setting': {'enabled': true}};
  @override
  Future<dynamic> get(String path, {Map<String, dynamic>? queryParameters}) async => {
    'id': 'school', 'name': 'School', 'slug': 'school', 'segment': 'preschool',
    'is_active': true, 'features': features, 'resolved_features': features,
  };
  @override
  Future<dynamic> patch(String path, {dynamic data}) async {
    features = Map<String, dynamic>.from(data['features'] as Map);
    return get(path);
  }
}

void main() {
  testWidgets('owner adds, renames and disables a role without dropping settings', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = _SchoolApi();
    await tester.pumpWidget(ProviderScope(
      overrides: [apiClientProvider.overrideWithValue(api)],
      child: const MaterialApp(home: SchoolConfigScreen(schoolId: 'school', schoolName: 'School')),
    ));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Adicionar função'), 600,
      scrollable: find.byWidgetPredicate((widget) =>
          widget is Scrollable && widget.axisDirection == AxisDirection.down).first);
    await tester.tap(find.text('Adicionar função'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Recepção');
    await tester.tap(find.text('Guardar função'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    final roles = api.features['custom_roles'] as List;
    expect(roles.single['label'], 'Recepção');
    expect(roles.single['base_role'], 'secretary');
    expect(api.features['external_setting'], {'enabled': true});
    final key = roles.single['key'];
    await tester.ensureVisible(find.text('Recepção'));
    await tester.tap(find.text('Recepção'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Assistente de Secretaria');
    await tester.tap(find.text('Guardar função'));
    await tester.pumpAndSettle();
    final tile = find.ancestor(of: find.text('Assistente de Secretaria'), matching: find.byType(ListTile));
    await tester.tap(find.descendant(of: tile, matching: find.byType(Switch)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    final updated = (api.features['custom_roles'] as List).single;
    expect(updated['key'], key);
    expect(updated['label'], 'Assistente de Secretaria');
    expect(updated['enabled'], false);
    expect(api.features['external_setting'], {'enabled': true});
    expect(tester.takeException(), isNull);
  });
}
