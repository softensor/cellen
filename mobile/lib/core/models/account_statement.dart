/// A guardian account statement, whichever engine produced it.
///
/// Cellen's internal report returns `total_invoiced` / `total_settled` /
/// `current_balance` / `credit_balance` / `movements[]`; FinReg returns
/// `opening_balance` / `closing_balance` / `transactions[]`. Parsing both
/// here keeps the parent portal and the admin statement screen from reading
/// one shape and silently rendering zeros for the other.
class AccountStatement {
  final double totalInvoiced;
  final double totalSettled;
  final double currentBalance;
  final double creditBalance;
  final List<AccountMovement> movements;

  const AccountStatement({
    required this.totalInvoiced,
    required this.totalSettled,
    required this.currentBalance,
    required this.creditBalance,
    required this.movements,
  });

  factory AccountStatement.fromJson(Map<String, dynamic> json) {
    final raw = (json['movements'] ?? json['transactions'] ?? const []) as List;
    final movements = raw
        .whereType<Map>()
        .map((row) => AccountMovement.fromJson(Map<String, dynamic>.from(row)))
        .toList();

    final totalInvoiced = _number(json['total_invoiced']) ??
        movements.fold<double>(0, (sum, movement) => sum + movement.debit);
    final totalSettled = _number(json['total_settled']) ??
        movements.fold<double>(0, (sum, movement) => sum + movement.credit);
    final currentBalance = _number(json['current_balance']) ??
        _number(json['closing_balance']) ??
        totalInvoiced - totalSettled;
    final creditBalance = _number(json['credit_balance']) ??
        (currentBalance < 0 ? -currentBalance : 0);

    return AccountStatement(
      totalInvoiced: totalInvoiced,
      totalSettled: totalSettled,
      currentBalance: currentBalance,
      creditBalance: creditBalance,
      movements: movements,
    );
  }
}

class AccountMovement {
  final String date;
  final String description;
  final String documentNumber;
  final double debit;
  final double credit;
  final double? runningBalance;

  const AccountMovement({
    required this.date,
    required this.description,
    required this.documentNumber,
    required this.debit,
    required this.credit,
    this.runningBalance,
  });

  factory AccountMovement.fromJson(Map<String, dynamic> json) {
    final type = json['type']?.toString() ?? '';
    final label = json['description']?.toString() ??
        json['document_type_label']?.toString() ??
        type;
    return AccountMovement(
      date: json['date']?.toString() ??
          json['transaction_date']?.toString() ??
          '',
      description: label,
      documentNumber: json['document_number']?.toString() ?? '',
      debit: _number(json['debit']) ?? 0,
      credit: _number(json['credit']) ?? 0,
      runningBalance:
          _number(json['running_balance']) ?? _number(json['balance']),
    );
  }
}

double? _number(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}
