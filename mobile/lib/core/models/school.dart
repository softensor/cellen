class School {
  final String id;
  final String name;
  final String slug;
  final String? address;
  final String? phone;
  final String? email;
  final String? logoUrl;
  final String currency;
  final bool isActive;
  final bool waEnabled;
  final String? waPhoneNumberId;
  final String segment;
  final Map<String, dynamic> resolvedFeatures;

  const School({
    required this.id,
    required this.name,
    required this.slug,
    this.address,
    this.phone,
    this.email,
    this.logoUrl,
    this.currency = 'AOA',
    required this.isActive,
    this.waEnabled = false,
    this.waPhoneNumberId,
    this.segment = 'preschool',
    this.resolvedFeatures = const {},
  });

  /// Returns true if feature is enabled. Missing key defaults to true
  /// so existing schools without feature data are unaffected.
  bool hasFeature(String key) {
    if (!resolvedFeatures.containsKey(key)) return true;
    return resolvedFeatures[key] as bool? ?? true;
  }

  factory School.fromJson(Map<String, dynamic> json) {
    final rf = json['resolved_features'];
    return School(
      id: json['id']?.toString() ?? '',
      name: json['name'] as String? ?? '',
      slug: json['slug'] as String? ?? '',
      address: json['address'] as String?,
      phone: json['phone'] as String?,
      email: json['email'] as String?,
      logoUrl: json['logo_url'] as String?,
      currency: json['currency'] as String? ?? 'AOA',
      isActive: json['is_active'] as bool? ?? true,
      waEnabled: json['wa_enabled'] as bool? ?? false,
      waPhoneNumberId: json['wa_phone_number_id'] as String?,
      segment: json['segment'] as String? ?? 'preschool',
      resolvedFeatures: rf is Map ? Map<String, dynamic>.from(rf) : {},
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'slug': slug,
        if (address != null) 'address': address,
        if (phone != null) 'phone': phone,
        if (email != null) 'email': email,
        if (logoUrl != null) 'logo_url': logoUrl,
        'currency': currency,
        'is_active': isActive,
        'segment': segment,
      };
}
