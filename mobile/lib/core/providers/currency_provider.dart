import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../api/api_client.dart';
import '../auth/auth_provider.dart';
import '../models/school.dart';

/// Fetches basic school info (including currency) for any authenticated user.
/// Not autoDispose — cached app-wide so the sidebar always has school branding.
final schoolInfoProvider = FutureProvider<School>((ref) async {
  // Re-fetch school-scoped configuration whenever the authenticated session
  // changes. This prevents role options from a previous login being reused.
  ref.watch(authProvider.select(
      (auth) => (auth.isAuthenticated, auth.schoolId, auth.accessToken)));
  final api = ref.read(apiClientProvider);
  final data = await api.get('/schools/info');
  return School.fromJson(data as Map<String, dynamic>);
});

/// Returns the currency symbol for a given ISO currency code.
String _currencySymbol(String currencyCode) {
  switch (currencyCode.toUpperCase()) {
    case 'AOA':
      return 'Kz';
    case 'EUR':
      return '€';
    case 'USD':
      return '\$';
    case 'GBP':
      return '£';
    default:
      return currencyCode;
  }
}

/// Returns the locale string for formatting numbers for a given currency.
String _localeForCurrency(String currencyCode) {
  switch (currencyCode.toUpperCase()) {
    case 'AOA':
      return 'pt_AO';
    case 'EUR':
      return 'pt_PT';
    case 'USD':
      return 'en_US';
    case 'GBP':
      return 'en_GB';
    default:
      return 'pt_AO';
  }
}

/// A [NumberFormat] configured for the school's currency.
/// Falls back to AOA/Kz if the school info cannot be fetched.
final currencyFormatProvider = Provider.autoDispose<NumberFormat>((ref) {
  final schoolAsync = ref.watch(schoolInfoProvider);
  final currency = schoolAsync.maybeWhen(
    data: (school) => school.currency,
    orElse: () => 'AOA',
  );
  return NumberFormat.currency(
    locale: _localeForCurrency(currency),
    symbol: _currencySymbol(currency),
  );
});
