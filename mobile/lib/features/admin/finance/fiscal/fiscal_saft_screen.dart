import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/api/api_client.dart';
import '../../../../core/api/api_exception.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/download_helper.dart'
    if (dart.library.html) '../../../../core/utils/download_helper_web.dart';

/// Monthly SAF-T (AO) sales export. FinReg generates the file; Cellen only
/// asks for the month and hands the file to the person.
class FiscalSaftScreen extends ConsumerStatefulWidget {
  const FiscalSaftScreen({super.key});

  @override
  ConsumerState<FiscalSaftScreen> createState() => _FiscalSaftScreenState();
}

class _FiscalSaftScreenState extends ConsumerState<FiscalSaftScreen> {
  final _iso = DateFormat('yyyy-MM-dd');
  final _label = DateFormat('MMMM yyyy', 'pt_PT');
  String? _downloading;
  String? _error;

  List<DateTime> get _months {
    final now = DateTime.now();
    return List.generate(18, (index) => DateTime(now.year, now.month - index));
  }

  Future<void> _export(DateTime month) async {
    final from = DateTime(month.year, month.month, 1);
    final last = DateTime(month.year, month.month + 1, 0);
    final today = DateTime.now();
    final to = last.isAfter(today) ? today : last;
    final key = _iso.format(from);
    setState(() {
      _downloading = key;
      _error = null;
    });
    try {
      final bytes = await ref.read(apiClientProvider).getBytes(
          '/finreg/reports/saft-sales?date_from=${_iso.format(from)}&date_to=${_iso.format(to)}');
      final filename = 'SAFT_AO_Faturacao_${_iso.format(from)}_${_iso.format(to)}.xml';
      if (kIsWeb) {
        downloadXml(utf8.decode(bytes), filename);
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('$filename descarregado.')));
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('A exportação SAF-T é descarregada na versão web do Cellen.'),
        ));
      }
    } catch (error) {
      setState(() => _error = apiErrorMessage(error));
    } finally {
      if (mounted) setState(() => _downloading = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Exportar SAF-T')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text(
          'O ficheiro SAF-T (AO) de faturação é gerado pelo sistema fiscal certificado para o mês escolhido e pode ser entregue à AGT.',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_error!, style: const TextStyle(color: AppTheme.danger)),
          ),
        const SizedBox(height: 12),
        for (final month in _months)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: const BorderSide(color: AppTheme.border),
            ),
            child: ListTile(
              leading: const Icon(Icons.description_outlined),
              title: Text(_capitalize(_label.format(month))),
              trailing: _downloading == _iso.format(DateTime(month.year, month.month, 1))
                  ? const SizedBox(
                      width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.download_outlined),
              onTap: _downloading == null ? () => _export(month) : null,
            ),
          ),
      ]),
    );
  }

  String _capitalize(String value) =>
      value.isEmpty ? value : value[0].toUpperCase() + value.substring(1);
}
