class Payment {
  final String id;
  final String billingGuardianId;
  final double amount;
  final DateTime paymentDate;
  final String paymentMethod; // cash, bank_transfer, card, check
  final String status;
  final String? notes;

  const Payment({
    required this.id,
    required this.billingGuardianId,
    required this.amount,
    required this.paymentDate,
    required this.paymentMethod,
    this.status = 'confirmed',
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
      billingGuardianId: json['billing_guardian_id']?.toString() ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      paymentDate: json['payment_date'] != null
          ? DateTime.tryParse(json['payment_date'] as String) ?? DateTime.now()
          : DateTime.now(),
      paymentMethod: json['payment_method'] as String? ?? 'cash',
      status: json['status'] as String? ?? 'confirmed',
      notes: json['notes'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'billing_guardian_id': billingGuardianId,
        'amount': amount,
        'payment_date':
            '${paymentDate.year.toString().padLeft(4, '0')}-${paymentDate.month.toString().padLeft(2, '0')}-${paymentDate.day.toString().padLeft(2, '0')}',
        'payment_method': paymentMethod,
        if (notes != null) 'notes': notes,
      };
}
