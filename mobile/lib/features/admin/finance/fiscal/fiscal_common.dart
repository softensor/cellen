import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../../../core/api/api_client.dart';
import '../../../../core/api/api_exception.dart';
import '../../../../core/theme/app_theme.dart';

/// Shared pieces of Cellen's native fiscal screens.
///
/// Every value these screens show was returned by FinReg through Cellen's
/// backend; the app never computes a fiscal number, total or status.

/// A random RFC 4122 v4 id. A screen mints one per action (one correction,
/// one invoice) so pressing again after a timeout resends the same request.
String newRequestId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  String hex(int start, int end) => bytes
      .sublist(start, end)
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
}

/// The school-facing state the backend derives from FinReg's document and
/// AGT status (`processing`, `submitted`, `issued`, `rejected`, `cancelled`).
class FiscalState {
  final String label;
  final Color color;
  final IconData icon;
  const FiscalState(this.label, this.color, this.icon);

  static FiscalState of(String? state) {
    switch (state) {
      case 'processing':
        return const FiscalState(
            'Em processamento', AppTheme.textSecondary, Icons.hourglass_top);
      case 'submitted':
        return const FiscalState(
            'Enviada à AGT', AppTheme.secondary, Icons.cloud_upload_outlined);
      case 'issued':
        return const FiscalState(
            'Emitida', AppTheme.success, Icons.verified_outlined);
      case 'rejected':
        return const FiscalState(
            'Rejeitada pela AGT', AppTheme.danger, Icons.error_outline);
      case 'cancelled':
        return const FiscalState(
            'Anulada', AppTheme.warning, Icons.block_outlined);
      case 'confirmed':
        return const FiscalState(
            'Concluído', AppTheme.success, Icons.check_circle_outline);
      default:
        return const FiscalState(
            'Desconhecido', AppTheme.textSecondary, Icons.help_outline);
    }
  }
}

class FiscalStateChip extends StatelessWidget {
  final String? state;
  final bool dense;
  const FiscalStateChip({super.key, required this.state, this.dense = false});

  @override
  Widget build(BuildContext context) {
    final look = FiscalState.of(state);
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: dense ? 6 : 8, vertical: dense ? 2 : 4),
      decoration: BoxDecoration(
        color: look.color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(look.icon, size: dense ? 12 : 14, color: look.color),
        const SizedBox(width: 4),
        Text(look.label,
            style: TextStyle(
                fontSize: dense ? 11 : 12,
                color: look.color,
                fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

String fiscalKindLabel(String? kind) {
  switch (kind) {
    case 'invoice':
      return 'Fatura';
    case 'invoice_receipt':
      return 'Fatura-recibo';
    case 'credit_note':
      return 'Nota de crédito';
    case 'debit_note':
      return 'Nota de débito';
    case 'receipt':
      return 'Recibo';
    default:
      return 'Documento';
  }
}

String paymentMethodLabel(String? method) {
  switch (method) {
    case 'cash':
      return 'Numerário';
    case 'transfer':
      return 'Transferência';
    case 'card':
      return 'Cartão';
    case 'check':
      return 'Cheque';
    case 'mobile':
      return 'Pagamento móvel';
    case 'reference':
      return 'Referência';
    default:
      return method ?? '—';
  }
}

/// `2026-11-03` → `03/11/2026`; anything else unchanged.
String fiscalDate(String? iso) {
  if (iso == null || iso.length < 10) return iso ?? '—';
  final parts = iso.substring(0, 10).split('-');
  if (parts.length != 3) return iso;
  return '${parts[2]}/${parts[1]}/${parts[0]}';
}

/// Fetches an official PDF through Cellen's backend and opens the system
/// share/print sheet. Errors are shown in the person's words.
Future<void> openFiscalPdf(
  BuildContext context,
  WidgetRef ref, {
  required String path,
  required String filename,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final bytes = await ref.read(apiClientProvider).getBytes(path);
    await Printing.sharePdf(bytes: bytes, filename: filename);
  } catch (error) {
    messenger.showSnackBar(SnackBar(content: Text(apiErrorMessage(error))));
  }
}

class FiscalEmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  const FiscalEmptyState(
      {super.key, required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 56, color: AppTheme.textSecondary),
          const SizedBox(height: 12),
          Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.textSecondary)),
        ]),
      ),
    );
  }
}

class FiscalSearchField extends StatefulWidget {
  final String hint;
  final ValueChanged<String> onSubmitted;
  const FiscalSearchField(
      {super.key, required this.hint, required this.onSubmitted});

  @override
  State<FiscalSearchField> createState() => _FiscalSearchFieldState();
}

class _FiscalSearchFieldState extends State<FiscalSearchField> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      textInputAction: TextInputAction.search,
      onSubmitted: (value) => widget.onSubmitted(value.trim()),
      decoration: InputDecoration(
        hintText: widget.hint,
        prefixIcon: const Icon(Icons.search),
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        suffixIcon: IconButton(
          icon: const Icon(Icons.clear),
          onPressed: () {
            _controller.clear();
            widget.onSubmitted('');
          },
        ),
      ),
    );
  }
}
