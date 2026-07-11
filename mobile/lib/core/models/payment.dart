class Payment {
  final String id;
  final String invoiceId;
  final String? childName;
  final double amount;
  final DateTime paymentDate;
  final String paymentMethod; // cash, bank_transfer, card, check
  final String? reference;
  final String? notes;

  const Payment({
    required this.id,
    required this.invoiceId,
    this.childName,
    required this.amount,
    required this.paymentDate,
    required this.paymentMethod,
    this.reference,
    this.notes,
  });

  String get paymentMethodLabel {
    switch (paymentMethod) {
      case 'cash':
        return 'Numerário';
      case 'bank_transfer':
        return 'Transferência';
      case 'card':
        return 'Cartão';
      case 'check':
        return 'Cheque';
      default:
        return paymentMethod;
    }
  }

  factory Payment.fromJson(Map<String, dynamic> json) {
    return Payment(
      id: json['id']?.toString() ?? '',
      invoiceId: json['invoice_id']?.toString() ?? '',
      childName: json['child_name'] as String?,
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      paymentDate: json['payment_date'] != null
          ? DateTime.tryParse(json['payment_date'] as String) ?? DateTime.now()
          : DateTime.now(),
      paymentMethod: json['payment_method'] as String? ?? 'cash',
      reference: json['reference'] as String?,
      notes: json['notes'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'invoice_id': invoiceId,
        'amount': amount,
        'payment_date':
            '${paymentDate.year.toString().padLeft(4, '0')}-${paymentDate.month.toString().padLeft(2, '0')}-${paymentDate.day.toString().padLeft(2, '0')}',
        'payment_method': paymentMethod,
        if (reference != null) 'reference': reference,
        if (notes != null) 'notes': notes,
      };
}
