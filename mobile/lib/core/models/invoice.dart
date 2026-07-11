class Invoice {
  final String id;
  final String childId;
  final String? childName;
  final DateTime invoiceDate;
  final DateTime referenceMonth;
  final String? description;
  final double tuitionAmount;
  final double otherFees;
  final double totalAmount;
  final String status; // pending, partially_paid, paid, cancelled, overdue
  final DateTime? dueDate;

  const Invoice({
    required this.id,
    required this.childId,
    this.childName,
    required this.invoiceDate,
    required this.referenceMonth,
    this.description,
    required this.tuitionAmount,
    required this.otherFees,
    required this.totalAmount,
    required this.status,
    this.dueDate,
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
      invoiceDate: json['invoice_date'] != null
          ? DateTime.tryParse(json['invoice_date'] as String) ?? DateTime.now()
          : DateTime.now(),
      referenceMonth: json['reference_month'] != null
          ? DateTime.tryParse(json['reference_month'] as String) ??
              DateTime.now()
          : DateTime.now(),
      description: json['description'] as String?,
      tuitionAmount:
          (json['tuition_amount'] as num?)?.toDouble() ?? 0.0,
      otherFees: (json['other_fees'] as num?)?.toDouble() ?? 0.0,
      totalAmount: (json['total_amount'] as num?)?.toDouble() ?? 0.0,
      status: json['status'] as String? ?? 'pending',
      dueDate: json['due_date'] != null
          ? DateTime.tryParse(json['due_date'] as String)
          : null,
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
        'tuition_amount': tuitionAmount,
        'other_fees': otherFees,
        'total_amount': totalAmount,
        'status': status,
        if (dueDate != null)
          'due_date':
              '${dueDate!.year.toString().padLeft(4, '0')}-${dueDate!.month.toString().padLeft(2, '0')}-${dueDate!.day.toString().padLeft(2, '0')}',
      };
}
