import 'package:flutter/material.dart';
import 'role_definitions.dart';

class CustomRole {
  final String key;
  final String label;
  final List<String> permissions;
  final bool enabled;
  const CustomRole(
      {required this.key,
      required this.label,
      required this.permissions,
      this.enabled = true});

  factory CustomRole.fromJson(Map<String, dynamic> json) => CustomRole(
        key: json['key'] as String,
        label: json['label'] as String,
        permissions: (json['permissions'] as List? ??
                [
                  if (_legacyPermission[json['base_role']] != null)
                    _legacyPermission[json['base_role']]!,
                ])
            .map((value) => value.toString())
            .toList(),
        enabled: json['enabled'] as bool? ?? true,
      );

  Map<String, dynamic> toJson() => {
        'key': key,
        'label': label,
        'permissions': permissions,
        'enabled': enabled,
      };

  RoleDef get definition {
    final features = <String>{};
    for (final permission in permissions) {
      features.addAll(customPermissionFeatures[permission] ?? const []);
    }
    return RoleDef(
      key: key,
      label: label,
      description: permissions.isEmpty
          ? 'Sem acessos atribuídos'
          : '${permissions.length} área(s) de acesso atribuída(s)',
      icon: Icons.badge_outlined,
      color: Colors.deepPurple,
      defaultFeatures: features.toList(),
    );
  }
}

const customPermissionFeatures = <String, List<String>>{
  'school_administration': [
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
  ],
  'academic_coordination': [
    'checkin',
    'lesson_attendance',
    'caderneta',
    'evaluations',
    'timetable_k12',
    'grades',
    'subjects',
    'report_cards',
    'activities',
    'absences',
  ],
  'finance': ['finance'],
  'secretariat': [
    'appointments',
    'absences',
    'events',
    'documents',
    'announcements',
    'messages',
  ],
  'teaching': [
    'checkin',
    'lesson_attendance',
    'caderneta',
    'grades',
    'evaluations',
    'timetable_k12',
    'activities',
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
  'health': ['health', 'immunizations', 'med_report', 'incidents'],
};

const _legacyPermission = <dynamic, String>{
  'coordinator': 'academic_coordination',
  'finance_officer': 'finance',
  'secretary': 'secretariat',
  'teacher': 'teaching',
  'nurse': 'health',
};

List<CustomRole> customRolesFromFeatures(Map<String, dynamic> features) =>
    (features['custom_roles'] as List? ?? const [])
        .map((entry) =>
            CustomRole.fromJson(Map<String, dynamic>.from(entry as Map)))
        .toList();

List<RoleDef> staffRolesForFeatures(Map<String, dynamic> features) => [
      ...kStaffRoles,
      for (final role in customRolesFromFeatures(features)) role.definition,
    ];
