// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/app_theme.dart';

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------
class SaftScreen extends ConsumerStatefulWidget {
  const SaftScreen({super.key});

  @override
  ConsumerState<SaftScreen> createState() => _SaftScreenState();
}

class _SaftScreenState extends ConsumerState<SaftScreen> {
  DateTime _fromDate = DateTime(DateTime.now().year, 1, 1);
  DateTime _toDate = DateTime.now();
  bool _isLoading = false;
  String? _error;
  bool _success = false;

  Future<void> _pickFromDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _fromDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _fromDate = picked);
  }

  Future<void> _pickToDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _toDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _toDate = picked);
  }

  Future<void> _generateSaft() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _success = false;
    });
    try {
      final api = ref.read(apiClientProvider);
      final fmt = DateFormat('yyyy-MM-dd');
      final data = await api.get(
        '/finance/reports/saft',
        queryParameters: {
          'from_date': fmt.format(_fromDate),
          'to_date': fmt.format(_toDate),
        },
      );

      final xmlContent = data is String ? data : data.toString();

      // Trigger download via dart:html on web
      final blob = html.Blob([xmlContent], 'application/xml');
      final url = html.Url.createObjectUrlFromBlob(blob);
      final anchor = html.AnchorElement(href: url)
        ..setAttribute('download', 'SAFT_${DateTime.now().year}.xml')
        ..click();
      html.Url.revokeObjectUrl(url);

      setState(() {
        _isLoading = false;
        _success = true;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fmt = DateFormat('dd/MM/yyyy');

    return Scaffold(
      appBar: AppBar(title: const Text('Exportar SAF-T AO')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryLight,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.file_download_outlined,
                              color: AppTheme.primary, size: 28),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'SAF-T AO',
                                style: theme.textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 2),
                              const Text(
                                'Exportação fiscal normalizada',
                                style: TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFFCD34D)),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline,
                              color: AppTheme.warning, size: 20),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'O ficheiro SAF-T-AO é exigido pela AGT para auditoria fiscal. '
                              'O ficheiro gerado deve ser submetido nos prazos legais.',
                              style: TextStyle(
                                  color: AppTheme.warning,
                                  fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text('Período',
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: _pickFromDate,
                            borderRadius: BorderRadius.circular(8),
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'De',
                                prefixIcon:
                                    Icon(Icons.calendar_today, size: 18),
                              ),
                              child: Text(fmt.format(_fromDate)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: InkWell(
                            onTap: _pickToDate,
                            borderRadius: BorderRadius.circular(8),
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Até',
                                prefixIcon:
                                    Icon(Icons.calendar_today, size: 18),
                              ),
                              child: Text(fmt.format(_toDate)),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    if (_success)
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: AppTheme.statusBg('present'),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.check_circle_outline,
                                color: AppTheme.success, size: 20),
                            SizedBox(width: 8),
                            Text(
                              'Ficheiro SAF-T gerado e transferido com sucesso.',
                              style: TextStyle(
                                  color: AppTheme.success,
                                  fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    if (_error != null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: AppTheme.statusBg('absent'),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(_error!,
                            style: const TextStyle(color: AppTheme.danger)),
                      ),
                    FilledButton.icon(
                      onPressed: _isLoading ? null : _generateSaft,
                      icon: _isLoading
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.download),
                      label: Text(
                          _isLoading ? 'A gerar...' : 'Gerar SAF-T'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
