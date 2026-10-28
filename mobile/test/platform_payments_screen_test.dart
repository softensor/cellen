import 'package:cellen/core/api/api_client.dart';
import 'package:cellen/core/api/api_exception.dart';
import 'package:cellen/features/platform/payments/platform_payments_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

const _connectedStatus = {
  'configured': true,
  'enabled': true,
  'provider': 'principia_pay',
  'source_system': 'cellen',
  'status': 'connected',
  'token_prefix': 'ppt_live_tok',
  'token_source': 'admin',
  'last_error': null,
  'last_checked_at': null,
};

class _FakeApi extends ApiClient {
  _FakeApi()
      : status = Map<String, dynamic>.from(_connectedStatus),
        super(const FlutterSecureStorage());

  Map<String, dynamic> status;
  final List<String> postPaths = [];
  final List<dynamic> postData = [];
  Object? postError;

  @override
  Future<dynamic> get(String path,
      {Map<String, dynamic>? queryParameters, Duration? receiveTimeout}) async {
    if (path == '/platform/payments/status') return status;
    if (path == '/platform/payments/schools') {
      return {
        'configured': status['configured'],
        'rail_error': null,
        'schools': [
          {
            'id': 'school-1',
            'name': 'Escola Rainha Njinga',
            'rail_state': 'unregistered',
            'registered': false,
            'providers': <String, dynamic>{},
          },
          {
            'id': 'school-2',
            'name': 'Escola Sem Conta',
            'rail_state': 'needs_credentials',
            'registered': true,
            'providers': {'appypay': 'verified'},
          },
        ],
      };
    }
    return <dynamic>[];
  }

  @override
  Future<dynamic> post(String path,
      {dynamic data, Duration? receiveTimeout}) async {
    postPaths.add(path);
    postData.add(data);
    if (postError != null) throw postError!;
    return status;
  }
}

Future<_FakeApi> _pump(WidgetTester tester, {_FakeApi? api}) async {
  final fake = api ?? _FakeApi();
  await tester.pumpWidget(ProviderScope(
    overrides: [apiClientProvider.overrideWithValue(fake)],
    child: const MaterialApp(
      locale: Locale('pt'),
      supportedLocales: [Locale('pt'), Locale('en')],
      localizationsDelegates: [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: PlatformPaymentsScreen(),
    ),
  ));
  await tester.pumpAndSettle();
  return fake;
}

void main() {
  testWidgets('the owner sees the rail state of every school', (tester) async {
    final api = await _pump(tester);

    expect(find.text('principia-pay activo'), findsOneWidget);
    expect(find.textContaining('ppt_live_tok'), findsOneWidget);
    expect(find.text('Escola Rainha Njinga'), findsOneWidget);
    expect(find.text('Não registada'), findsOneWidget);
    expect(find.text('Faltam credenciais do fornecedor'), findsOneWidget);
    expect(find.textContaining('appypay: verificado'), findsOneWidget);

    final register = find.widgetWithText(TextButton, 'Registar escola');
    expect(register, findsOneWidget);
    expect(tester.widget<TextButton>(register).onPressed, isNotNull);
    expect(api.postPaths, isEmpty);
  });

  testWidgets('activation posts the pasted product token', (tester) async {
    final api = await _pump(tester);

    await tester.enterText(find.byType(TextField), 'ppt_live_token');
    await tester.tap(find.widgetWithText(FilledButton, 'Activar'));
    await tester.pumpAndSettle();

    expect(api.postPaths, ['/platform/payments/activate']);
    expect(api.postData.single, {'product_token': 'ppt_live_token'});
    expect(find.text('principia-pay activo.'), findsOneWidget);
  });

  testWidgets('a refused activation keeps the error visible', (tester) async {
    final api = _FakeApi();
    api.postError =
        const ApiException(statusCode: 400, message: 'Token inválido');
    await _pump(tester, api: api);

    await tester.enterText(find.byType(TextField), 'ppt_wrong');
    await tester.tap(find.widgetWithText(FilledButton, 'Activar'));
    await tester.pumpAndSettle();

    expect(
      find.text('Activação falhou: Token inválido'),
      findsOneWidget,
    );
  });

  testWidgets('registering a school calls the platform route', (tester) async {
    final api = await _pump(tester);

    final register = find.widgetWithText(TextButton, 'Registar escola');
    await tester.ensureVisible(register);
    await tester.pumpAndSettle();
    await tester.tap(register);
    await tester.pumpAndSettle();

    expect(api.postPaths, ['/platform/payments/schools/school-1/register']);
    expect(find.text('Escola Rainha Njinga registada no principia-pay.'),
        findsOneWidget);
  });
}
