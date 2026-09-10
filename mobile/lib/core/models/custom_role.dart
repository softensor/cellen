import 'package:flutter/material.dart';
import 'role_definitions.dart';

class CustomRole {
  final String key;
  final String label;
  final List<String> permissions;
  final bool enabled;

  const CustomRole({
    required this.key,
    required this.label,
    required this.permissions,
    this.enabled = true,
  });

  factory CustomRole.fromJson(Map<String, dynamic> json) {
    final raw = json['permissions'] as List? ??
        [
          if (_legacyPermission[json['base_role']] != null)
            _legacyPermission[json['base_role']]!,
        ];
    return CustomRole(
      key: json['key'] as String,
      label: json['label'] as String,
      permissions: expandCustomPermissions(
          raw.map((value) => value.toString()).toList()),
      enabled: json['enabled'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
        'key': key,
        'label': label,
        'permissions': permissions,
        'enabled': enabled,
      };

  RoleDef get definition => RoleDef(
        key: key,
        label: label,
        description: permissions.isEmpty
            ? 'Sem funcionalidades atribuídas'
            : '${permissions.length} funcionalidade(s) atribuída(s)',
        icon: Icons.badge_outlined,
        color: Colors.deepPurple,
        defaultFeatures: permissions,
      );
}

List<String> expandCustomPermissions(List<String> values) {
  final result = <String>{};
  for (final value in values) {
    result.addAll(_legacyAreaPermissions[value] ?? [value]);
  }
  final sorted = result.toList()..sort();
  return sorted;
}

const _legacyAreaPermissions = <String, List<String>>{
  'school_administration': customPermissionKeys,
  'academic_coordination': [
    'academic',
    'checkin',
    'caderneta',
    'evaluations',
    'activities',
    'timetable_k12',
    'lesson_attendance',
    'grades',
    'subjects',
    'report_cards',
    'appointments',
    'absences',
    'reports',
  ],
  'finance': ['finance'],
  'secretariat': [
    'people',
    'academic',
    'appointments',
    'absences',
    'events',
    'documents',
    'announcements',
    'messages',
  ],
  'teaching': [
    'academic',
    'checkin',
    'caderneta',
    'evaluations',
    'activities',
    'timetable_k12',
    'lesson_attendance',
    'grades',
    'appointments',
  ],
  'staff_services': [
    'appointments',
    'meal_orders',
    'photos',
    'events',
    'documents',
    'announcements',
    'messages',
  ],
};

const _legacyPermission = <dynamic, String>{
  'coordinator': 'academic_coordination',
  'finance_officer': 'finance',
  'secretary': 'secretariat',
  'teacher': 'teaching',
  'nurse': 'health',
};

const customPermissionKeys = <String>[
  'people',
  'academic',
  'checkin',
  'caderneta',
  'evaluations',
  'activities',
  'timetable_k12',
  'lesson_attendance',
  'grades',
  'subjects',
  'report_cards',
  'appointments',
  'absences',
  'health',
  'immunizations',
  'med_report',
  'incidents',
  'meal_orders',
  'trip_auth',
  'pickup_auth',
  'photos',
  'events',
  'documents',
  'announcements',
  'messages',
  'finance',
  'reports',
  'school_settings',
];

List<CustomRole> customRolesFromFeatures(Map<String, dynamic> features) =>
    (features['custom_roles'] as List? ?? const [])
        .map((entry) =>
            CustomRole.fromJson(Map<String, dynamic>.from(entry as Map)))
        .toList();

List<RoleDef> staffRolesForFeatures(Map<String, dynamic> features) => [
      ...kStaffRoles,
      for (final role in customRolesFromFeatures(features)) role.definition,
    ];
