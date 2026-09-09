import 'package:flutter/material.dart';
import 'role_definitions.dart';

class CustomRole {
  final String key;
  final String label;
  final String baseRole;
  final bool enabled;
  const CustomRole(
      {required this.key,
      required this.label,
      required this.baseRole,
      this.enabled = true});

  factory CustomRole.fromJson(Map<String, dynamic> json) => CustomRole(
        key: json['key'] as String,
        label: json['label'] as String,
        baseRole: json['base_role'] as String,
        enabled: json['enabled'] as bool? ?? true,
      );

  Map<String, dynamic> toJson() => {
        'key': key,
        'label': label,
        'base_role': baseRole,
        'enabled': enabled,
      };

  RoleDef get definition {
    final base = roleDefByKey(baseRole);
    return RoleDef(
      key: key,
      label: label,
      description: 'Perfil de acesso: ${base?.label ?? baseRole}',
      icon: base?.icon ?? Icons.badge_outlined,
      color: base?.color ?? Colors.grey,
      featureFlag: 'role_$baseRole',
      defaultFeatures: base?.defaultFeatures ?? const [],
    );
  }
}

List<CustomRole> customRolesFromFeatures(Map<String, dynamic> features) =>
    (features['custom_roles'] as List? ?? const [])
        .map((entry) =>
            CustomRole.fromJson(Map<String, dynamic>.from(entry as Map)))
        .toList();

List<RoleDef> staffRolesForFeatures(Map<String, dynamic> features) => [
      ...kStaffRoles,
      for (final role in customRolesFromFeatures(features)) role.definition,
    ];
