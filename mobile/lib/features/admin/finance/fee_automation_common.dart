import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';

/// Active fiscal services used by fee policy, modalities and transport.
final feeBillingItemsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final data =
      await ref.read(apiClientProvider).get('/finance/billing-items') as List;
  return data.map((row) => Map<String, dynamic>.from(row as Map)).toList();
});

/// Students, used by the enrolment and transport assignment dialogs.
final feeStudentsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final data = await ref.read(apiClientProvider).get('/children') as List;
  return data.map((row) => Map<String, dynamic>.from(row as Map)).toList();
});

const _monthNames = <String>[
  'Janeiro',
  'Fevereiro',
  'Março',
  'Abril',
  'Maio',
  'Junho',
  'Julho',
  'Agosto',
  'Setembro',
  'Outubro',
  'Novembro',
  'Dezembro',
];

String billingMonthKey([DateTime? date]) {
  final value = date ?? DateTime.now();
  return '${value.year}-${value.month.toString().padLeft(2, '0')}';
}

DateTime parseBillingMonth(String key) {
  final parts = key.split('-');
  return DateTime(
    int.tryParse(parts.first) ?? DateTime.now().year,
    int.tryParse(parts.last) ?? DateTime.now().month,
  );
}

String billingMonthLabel(String key) {
  final value = parseBillingMonth(key);
  return '${_monthNames[value.month - 1]} ${value.year}';
}

/// Formats an ISO date without relying on locale data being initialised.
String formatIsoDate(String? iso) {
  if (iso == null || iso.length < 10) return '—';
  return '${iso.substring(8, 10)}/${iso.substring(5, 7)}/${iso.substring(0, 4)}';
}

double parseMoney(String text) {
  var value = text.trim().replaceAll(' ', '');
  if (value.contains(',')) {
    value = value.replaceAll('.', '').replaceAll(',', '.');
  }
  return double.tryParse(value) ?? 0;
}

String moneyText(dynamic value) {
  final number = (value as num?)?.toDouble() ?? 0;
  return number == number.roundToDouble()
      ? number.toStringAsFixed(0)
      : number.toStringAsFixed(2);
}

Future<String?> pickBillingMonth(
  BuildContext context, {
  required String initial,
}) {
  final parsed = parseBillingMonth(initial);
  var month = parsed.month;
  var year = parsed.year;
  final now = DateTime.now();
  return showDialog<String>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setLocal) => AlertDialog(
        title: const Text('Mês de facturação'),
        content: Row(children: [
          Expanded(
            child: DropdownButtonFormField<int>(
              value: month,
              decoration: const InputDecoration(labelText: 'Mês'),
              items: [
                for (var index = 1; index <= 12; index++)
                  DropdownMenuItem(
                    value: index,
                    child: Text(_monthNames[index - 1]),
                  ),
              ],
              onChanged: (value) => setLocal(() => month = value ?? month),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonFormField<int>(
              value: year,
              decoration: const InputDecoration(labelText: 'Ano'),
              items: [
                for (var value = now.year - 5; value <= now.year + 1; value++)
                  DropdownMenuItem(value: value, child: Text('$value')),
              ],
              onChanged: (value) => setLocal(() => year = value ?? year),
            ),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              '$year-${month.toString().padLeft(2, '0')}',
            ),
            child: const Text('Escolher'),
          ),
        ],
      ),
    ),
  );
}
