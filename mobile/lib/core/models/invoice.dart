class Invoice {
  final String id;
  final String childId;
  final String? childName;
  final String? billingGuardianId;
  final DateTime invoiceDate;
  final DateTime referenceMonth;
  final String? description;
  final double totalAmount;
  final String status; // pending, partially_paid, paid, cancelled, overdue
  final DateTime? dueDate;
  final String? fullDocumentNumber;
  final double balance;
  final double amountPaid;

  const Invoice({
    required this.id,
    required this.childId,
    this.childName,
    this.billingGuardianId,
    required this.invoiceDate,
    required this.referenceMonth,
    this.description,
    required this.totalAmount,
    required this.status,
    this.dueDate,
    this.fullDocumentNumber,
    this.balance = 0.0,
    this.amountPaid = 0.0,
  });

  bool get isPaid => status == 'paid';
  bool get isOverdue => status == 'overdue';
  bool get isPending => status == 'pending';
  bool get isCancelled => status == 'cancelled';
  bool get isPartiallyPaid => status == 'partially_paid';

  String get statusLabel {
    switch (status) {
      case 'paid':
        return 'Pago';
      case 'pending':
        return 'Pendente';
      case 'partially_paid':
        return 'Parcialmente Pago';
      case 'cancelled':
        return 'Cancelado';
      case 'overdue':
        return 'Em Atraso';
      default:
        return status;
    }
  }

  factory Invoice.fromJson(Map<String, dynamic> json) {
    return Invoice(
      id: json['id']?.toString() ?? '',
      childId: json['child_id']?.toString() ?? '',
      childName: json['child_name'] as String?,
      billingGuardianId: json['billing_guardian_id']?.toString(),
      invoiceDate: json['invoice_date'] != null
          ? DateTime.tryParse(json['invoice_date'] as String) ?? DateTime.now()
          : DateTime.now(),
      referenceMonth: json['reference_month'] != null
          ? DateTime.tryParse(json['reference_month'] as String) ??
              DateTime.now()
          : DateTime.now(),
      description: json['description'] as String?,
      // backend returns gross_total; fall back to total_amount for compat
      totalAmount: (json['gross_total'] as num?)?.toDouble() ??
          (json['total_amount'] as num?)?.toDouble() ??
          0.0,
      status: json['status'] as String? ?? 'pending',
      dueDate: json['due_date'] != null
          ? DateTime.tryParse(json['due_date'] as String)
          : null,
      fullDocumentNumber: json['full_document_number'] as String?,
      balance: (json['balance'] as num?)?.toDouble() ?? 0.0,
      amountPaid: (json['amount_paid'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'child_id': childId,
        'invoice_date':
            '${invoiceDate.year.toString().padLeft(4, '0')}-${invoiceDate.month.toString().padLeft(2, '0')}-${invoiceDate.day.toString().padLeft(2, '0')}',
        'reference_month':
            '${referenceMonth.year.toString().padLeft(4, '0')}-${referenceMonth.month.toString().padLeft(2, '0')}-${referenceMonth.day.toString().padLeft(2, '0')}',
        if (description != null) 'description': description,
        'gross_total': totalAmount,
        'status': status,
        if (dueDate != null)
          'due_date':
              '${dueDate!.year.toString().padLeft(4, '0')}-${dueDate!.month.toString().padLeft(2, '0')}-${dueDate!.day.toString().padLeft(2, '0')}',
      };
}
