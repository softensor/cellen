import 'package:flutter/material.dart';

/// Single source of truth for role definitions.
/// Consumed by: employee form (assignment), school config (permissions tab), sidebar builder.

class RoleDef {
  final String key;           // backend role string key
  final String label;         // display name (pt-PT)
  final String description;
  final IconData icon;
  final Color color;
  /// School feature flag that enables this role. Empty = always available.
  final String featureFlag;
  /// Feature keys this role can access by default (without explicit role_permissions).
  /// Features NOT in this list default to DENIED; can be granted per-school.
  final List<String> defaultFeatures;

  const RoleDef({
    required this.key,
    required this.label,
    required this.description,
    required this.icon,
    required this.color,
    this.featureFlag = '',
    this.defaultFeatures = const [],
  });

  bool get alwaysAvailable => featureFlag.isEmpty;
}

// ---------------------------------------------------------------------------
// Assignable staff roles — shown in employee form.
// Excludes: parent, student, platform_admin (not assigned via employee form).
// ---------------------------------------------------------------------------
const kStaffRoles = <RoleDef>[
  RoleDef(
    key: 'school_admin',
    label: 'Director / Administrador',
    description: 'Acesso completo a toda a gestão da escola',
    icon: Icons.admin_panel_settings_outlined,
    color: Colors.deepPurple,
    featureFlag: '', // always available
    defaultFeatures: [], // bypasses all feature checks
  ),
  RoleDef(
    key: 'coordinator',
    label: 'Coordenador Pedagógico',
    description: 'Gestão académica, horários, notas e pedagogia',
    icon: Icons.manage_accounts_outlined,
    color: Colors.teal,
    featureFlag: 'role_coordinator',
    defaultFeatures: [
      'checkin', 'lesson_attendance', 'caderneta', 'evaluations',
      'timetable_k12', 'grades', 'subjects', 'report_cards',
      'health', 'incidents', 'immunizations', 'med_report',
      'announcements', 'messages', 'documents', 'events', 'appointments',
      'activities', 'meal_orders', 'photos', 'absences',
    ],
  ),
  RoleDef(
    key: 'finance_officer',
    label: 'Director Financeiro',
    description: 'Acesso completo ao módulo financeiro',
    icon: Icons.account_balance_outlined,
    color: Colors.green,
    featureFlag: 'role_finance_officer',
    defaultFeatures: ['finance', 'announcements', 'messages', 'documents'],
  ),
  RoleDef(
    key: 'secretary',
    label: 'Secretaria',
    description: 'Matrículas, comunicação e dados de alunos/funcionários',
    icon: Icons.badge_outlined,
    color: Colors.orange,
    featureFlag: 'role_secretary',
    defaultFeatures: [
      'announcements', 'messages', 'documents', 'events', 'appointments', 'absences',
    ],
  ),
  RoleDef(
    key: 'teacher',
    label: 'Professor / Educador',
    description: 'Presenças, caderneta, saúde e comunicação',
    icon: Icons.school_outlined,
    color: Colors.blue,
    featureFlag: 'role_teacher',
    defaultFeatures: [
      'checkin', 'lesson_attendance', 'caderneta', 'grades', 'evaluations', 'timetable_k12',
      'health', 'immunizations', 'incidents',
      'announcements', 'messages', 'photos', 'events',
      'trip_auth', 'pickup_auth', 'meal_orders', 'appointments', 'documents',
    ],
  ),
  RoleDef(
    key: 'nurse',
    label: 'Enfermagem',
    description: 'Módulo de saúde, ocorrências e registos médicos',
    icon: Icons.medical_services_outlined,
    color: Colors.red,
    featureFlag: 'role_nurse',
    defaultFeatures: ['health', 'immunizations', 'med_report', 'incidents', 'messages'],
  ),
];

// ---------------------------------------------------------------------------
// Configurable roles — shown in school config permissions tab.
// Excludes school_admin (always full access, not configurable).
// Includes parent & student for restricting their portal access.
// ---------------------------------------------------------------------------
const kConfigRoles = <RoleDef>[
  RoleDef(
    key: 'coordinator',
    label: 'Coordenador Pedagógico',
    description: 'Gestão académica, horários, notas e pedagogia',
    icon: Icons.manage_accounts_outlined,
    color: Colors.teal,
    featureFlag: 'role_coordinator',
    defaultFeatures: [
      'checkin', 'lesson_attendance', 'caderneta', 'evaluations',
      'timetable_k12', 'grades', 'subjects', 'report_cards',
      'health', 'incidents', 'immunizations', 'med_report',
      'announcements', 'messages', 'documents', 'events', 'appointments',
      'activities', 'meal_orders', 'photos', 'absences',
    ],
  ),
  RoleDef(
    key: 'finance_officer',
    label: 'Director Financeiro',
    description: 'Acesso completo ao módulo financeiro',
    icon: Icons.account_balance_outlined,
    color: Colors.green,
    featureFlag: 'role_finance_officer',
    defaultFeatures: ['finance', 'announcements', 'messages', 'documents'],
  ),
  RoleDef(
    key: 'secretary',
    label: 'Secretaria',
    description: 'Matrículas, comunicação e dados de alunos/funcionários',
    icon: Icons.badge_outlined,
    color: Colors.orange,
    featureFlag: 'role_secretary',
    defaultFeatures: [
      'announcements', 'messages', 'documents', 'events', 'appointments', 'absences',
    ],
  ),
  RoleDef(
    key: 'teacher',
    label: 'Professor / Educador',
    description: 'Presenças, caderneta, saúde e comunicação',
    icon: Icons.school_outlined,
    color: Colors.blue,
    featureFlag: 'role_teacher',
    defaultFeatures: [
      'checkin', 'lesson_attendance', 'caderneta', 'grades', 'evaluations', 'timetable_k12',
      'health', 'immunizations', 'incidents',
      'announcements', 'messages', 'photos', 'events',
      'trip_auth', 'pickup_auth', 'meal_orders', 'appointments', 'documents',
    ],
  ),
  RoleDef(
    key: 'nurse',
    label: 'Enfermagem',
    description: 'Módulo de saúde, ocorrências e registos médicos',
    icon: Icons.medical_services_outlined,
    color: Colors.red,
    featureFlag: 'role_nurse',
    defaultFeatures: ['health', 'immunizations', 'med_report', 'incidents', 'messages'],
  ),
  RoleDef(
    key: 'parent',
    label: 'Encarregado de Educação',
    description: 'Portal do encarregado — saúde, finanças, comunicação',
    icon: Icons.family_restroom_outlined,
    color: Colors.purple,
    featureFlag: '',
    defaultFeatures: [
      'caderneta', 'grades', 'report_cards', 'health', 'incidents',
      'meal_orders', 'appointments', 'trip_auth', 'pickup_auth',
      'photos', 'events', 'announcements', 'messages', 'documents', 'finance',
    ],
  ),
  RoleDef(
    key: 'student',
    label: 'Aluno',
    description: 'Portal do aluno — boletim, documentos, calendário',
    icon: Icons.person_outlined,
    color: Colors.indigo,
    featureFlag: 'role_student',
    defaultFeatures: ['grades', 'report_cards', 'documents', 'events', 'announcements'],
  ),
];

/// Look up a [RoleDef] by its backend key. Returns null if not found.
RoleDef? roleDefByKey(String key) {
  for (final r in kStaffRoles) {
    if (r.key == key) return r;
  }
  for (final r in kConfigRoles) {
    if (r.key == key) return r;
  }
  return null;
}
