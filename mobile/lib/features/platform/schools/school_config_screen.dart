/// Platform-admin school configuration screen — full feature + role control.
///
/// What's configurable:
///   1. School segment (drives all defaults)
///   2. Every feature flag (all school-level capabilities)
///   3. Per-role feature permissions (which role can access which feature)
///
/// Persistence: PATCH /platform/schools/{id}
///   {segment, features: {key: bool|null, role_permissions: {role: {feature: bool}}}}
///
/// Design principle: defaults are defined by segment. Any explicit override is
/// stored in school.features. resolved_features = merge(defaults, overrides).
/// Resetting a toggle to its segment default removes the override (sends null).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/models/role_definitions.dart';
import '../../../core/providers/currency_provider.dart';
import '../../../core/theme/app_theme.dart';

// ---------------------------------------------------------------------------
// Segment defaults (mirrors app/models/school.py — keep in sync)
// ---------------------------------------------------------------------------

const _segmentDefaults = <String, Map<String, bool>>{
  'preschool': {
    'checkin': true, 'caderneta': true, 'evaluations': true, 'activities': true,
    'timetable_k12': false, 'lesson_attendance': false, 'grades': false, 'subjects': false,
    'report_cards': false, 'appointments': true,
    'health': true, 'immunizations': true, 'med_report': false, 'incidents': true,
    'meal_orders': true, 'trip_auth': true, 'pickup_auth': true,
    'photos': true, 'events': true, 'documents': true,
    'announcements': true, 'messages': true, 'finance': true,
    'absences': true, 'role_teacher': true, 'role_coordinator': true, 'role_finance_officer': true,
    'role_secretary': true, 'role_nurse': true, 'role_student': false,
  },
  'primary': {
    'checkin': false, 'caderneta': false, 'evaluations': false, 'activities': false,
    'timetable_k12': true, 'lesson_attendance': true, 'grades': true, 'subjects': true,
    'report_cards': true, 'appointments': true,
    'health': true, 'immunizations': true, 'med_report': true, 'incidents': true,
    'meal_orders': true, 'trip_auth': true, 'pickup_auth': true,
    'photos': true, 'events': true, 'documents': true,
    'announcements': true, 'messages': true, 'finance': true,
    'absences': true, 'role_teacher': true, 'role_coordinator': true, 'role_finance_officer': true,
    'role_secretary': true, 'role_nurse': true, 'role_student': false,
  },
  'secondary': {
    'checkin': false, 'caderneta': false, 'evaluations': false, 'activities': false,
    'timetable_k12': true, 'lesson_attendance': true, 'grades': true, 'subjects': true,
    'report_cards': true, 'appointments': false,
    'health': true, 'immunizations': false, 'med_report': true, 'incidents': true,
    'meal_orders': false, 'trip_auth': false, 'pickup_auth': false,
    'photos': false, 'events': true, 'documents': true,
    'announcements': true, 'messages': true, 'finance': true,
    'absences': true, 'role_teacher': true, 'role_coordinator': true, 'role_finance_officer': true,
    'role_secretary': true, 'role_nurse': false, 'role_student': true,
  },
  'combined': {
    'checkin': false, 'caderneta': false, 'evaluations': false, 'activities': false,
    'timetable_k12': true, 'lesson_attendance': true, 'grades': true, 'subjects': true,
    'report_cards': true, 'appointments': true,
    'health': true, 'immunizations': true, 'med_report': true, 'incidents': true,
    'meal_orders': true, 'trip_auth': true, 'pickup_auth': true,
    'photos': true, 'events': true, 'documents': true,
    'announcements': true, 'messages': true, 'finance': true,
    'absences': true, 'role_teacher': true, 'role_coordinator': true, 'role_finance_officer': true,
    'role_secretary': true, 'role_nurse': true, 'role_student': true,
  },
  'full': {
    'checkin': true, 'caderneta': true, 'evaluations': true, 'activities': true,
    'timetable_k12': true, 'lesson_attendance': true, 'grades': true, 'subjects': true,
    'report_cards': true, 'appointments': true,
    'health': true, 'immunizations': true, 'med_report': true, 'incidents': true,
    'meal_orders': true, 'trip_auth': true, 'pickup_auth': true,
    'photos': true, 'events': true, 'documents': true,
    'announcements': true, 'messages': true, 'finance': true,
    'absences': true, 'role_teacher': true, 'role_coordinator': true, 'role_finance_officer': true,
    'role_secretary': true, 'role_nurse': true, 'role_student': true,
  },
};

// ---------------------------------------------------------------------------
// Feature catalogue
// ---------------------------------------------------------------------------

enum _Cat { pedagogical, health, operational, comms, finance, roles }

class _Feat {
  final String key;
  final String label;
  final String description;
  final _Cat cat;
  final IconData icon;
  const _Feat(this.key, this.label, this.description, this.cat, this.icon);
}

const _allFeatures = <_Feat>[
  // Pedagógico
  _Feat('checkin',      'Presenças',                   'Registo diário de entradas e saídas dos alunos',                 _Cat.pedagogical, Icons.fact_check_outlined),
  _Feat('caderneta',    'Caderneta Diária',             'Relatório diário do educador / professor',                        _Cat.pedagogical, Icons.menu_book_outlined),
  _Feat('evaluations',  'Avaliações de Desenvolvimento','Fichas de avaliação por dimensões (Cognitivo, Motor…)',           _Cat.pedagogical, Icons.school_outlined),
  _Feat('activities',   'Actividades',                  'Planificação de actividades e horário semanal por grupo',         _Cat.pedagogical, Icons.sports_soccer_outlined),
  _Feat('timetable_k12',     'Horário Lectivo',          'Grade de horário: período × dia × disciplina × professor',        _Cat.pedagogical, Icons.table_chart_outlined),
  _Feat('lesson_attendance', 'Livro de Ponto',           'Registo de presenças e faltas por aula (K-12)',                   _Cat.pedagogical, Icons.how_to_reg_outlined),
  _Feat('grades',            'Notas',                   'Lançamento de notas por disciplina',                              _Cat.pedagogical, Icons.grade_outlined),
  _Feat('subjects',     'Disciplinas',                  'Cadastro de disciplinas e afectação por turma',                   _Cat.pedagogical, Icons.book_outlined),
  _Feat('report_cards', 'Boletins',                     'Geração e exportação de boletins escolares',                      _Cat.pedagogical, Icons.assignment_outlined),
  _Feat('appointments', 'Marcações',                    'Marcações e consultas com professores / coordenação',             _Cat.pedagogical, Icons.event_available_outlined),
  // Saúde
  _Feat('health',       'Saúde',                        'Registos de saúde, febre, medicamentos e bem-estar',              _Cat.health, Icons.health_and_safety_outlined),
  _Feat('immunizations','Vacinação',                    'Calendário vacinal e registos de imunização',                     _Cat.health, Icons.vaccines_outlined),
  _Feat('med_report',   'Relatório Médico',             'Relatório de saúde escolar e ficha médica',                       _Cat.health, Icons.medical_information_outlined),
  _Feat('incidents',    'Ocorrências',                  'Incidentes, acidentes e comportamentos notáveis',                 _Cat.health, Icons.report_outlined),
  // Operacional
  _Feat('meal_orders',  'Refeições',                    'Gestão de cantina e encomenda de refeições',                      _Cat.operational, Icons.restaurant_menu_outlined),
  _Feat('trip_auth',    'Autorizações de Visita',       'Autorizações digitais para visitas de estudo',                    _Cat.operational, Icons.directions_bus_outlined),
  _Feat('pickup_auth',  'Autorizações de Levantamento', 'Controlo de quem pode levantar o aluno',                         _Cat.operational, Icons.transfer_within_a_station_outlined),
  _Feat('photos',       'Galeria de Fotos',             'Galeria partilhada de fotos da escola',                           _Cat.operational, Icons.photo_library_outlined),
  _Feat('events',       'Calendário',                   'Eventos escolares e calendário partilhado',                       _Cat.operational, Icons.calendar_month_outlined),
  _Feat('documents',    'Documentos',                   'Repositório de documentos e circulares',                          _Cat.operational, Icons.folder_outlined),
  // Comunicação
  _Feat('announcements','Comunicados',                  'Anúncios e comunicados enviados a toda a comunidade',             _Cat.comms, Icons.campaign_outlined),
  _Feat('messages',     'Mensagens',                    'Mensagens privadas entre utilizadores',                           _Cat.comms, Icons.chat_bubble_outline),
  // Financeiro
  _Feat('finance',      'Módulo Financeiro',            'Facturas, contratos, despesas, caixa e exportação SAF-T',        _Cat.finance, Icons.account_balance_wallet_outlined),
  // Gestão de pessoal
  _Feat('absences',            'Faltas de Funcionários', 'Registo de faltas e ausências de funcionários',                  _Cat.operational, Icons.event_busy_outlined),
  // Funções disponíveis
  _Feat('role_teacher',        'Professor / Educador',  'Função de docente: caderneta, presenças, notas e saúde',         _Cat.roles, Icons.school_outlined),
  _Feat('role_coordinator',    'Coordenador Pedagógico','Acesso à gestão académica e relatórios pedagógicos',             _Cat.roles, Icons.manage_accounts_outlined),
  _Feat('role_finance_officer','Director Financeiro',   'Acesso completo ao módulo financeiro',                            _Cat.roles, Icons.account_balance_outlined),
  _Feat('role_secretary',      'Secretaria',            'Matrículas, comunicação e dados de alunos',                      _Cat.roles, Icons.badge_outlined),
  _Feat('role_nurse',          'Enfermagem',            'Módulo de saúde, ocorrências e registos médicos',                 _Cat.roles, Icons.medical_services_outlined),
  _Feat('role_student',        'Portal do Aluno',       'Acesso self-service: boletim, documentos, calendário',           _Cat.roles, Icons.person_outlined),
];

const _catLabels = {
  _Cat.pedagogical: 'Pedagógico',
  _Cat.health:      'Saúde & Incidentes',
  _Cat.operational: 'Operacional',
  _Cat.comms:       'Comunicação',
  _Cat.finance:     'Financeiro',
  _Cat.roles:       'Funções Disponíveis',
};

const _catIcons = {
  _Cat.pedagogical: Icons.menu_book_outlined,
  _Cat.health:      Icons.health_and_safety_outlined,
  _Cat.operational: Icons.settings_outlined,
  _Cat.comms:       Icons.forum_outlined,
  _Cat.finance:     Icons.account_balance_wallet_outlined,
  _Cat.roles:       Icons.people_outline,
};

// _rolePermDefs removed — using kConfigRoles from role_definitions.dart (single source of truth)

// Feature labels for the role permission matrix (shorter, for chips/cells)
const _featLabel = <String, String>{
  'checkin': 'Entradas/Saídas', 'caderneta': 'Caderneta',
  'evaluations': 'Avaliações Dev.', 'activities': 'Actividades',
  'timetable_k12': 'Horário', 'grades': 'Notas',
  'subjects': 'Disciplinas', 'report_cards': 'Boletins',
  'appointments': 'Marcações', 'health': 'Saúde',
  'immunizations': 'Vacinas', 'med_report': 'Rel. Médico',
  'incidents': 'Ocorrências', 'meal_orders': 'Refeições',
  'trip_auth': 'Visit. Estudo', 'pickup_auth': 'Levantamento',
  'photos': 'Galeria', 'events': 'Calendário',
  'documents': 'Documentos', 'announcements': 'Comunicados',
  'messages': 'Mensagens', 'finance': 'Financeiro',
  'lesson_attendance': 'Livro de Ponto', 'absences': 'Faltas Funcionários',
};

const _segments = [
  (value: 'preschool', label: 'Pré-Escolar',          icon: Icons.child_care_outlined,    color: Colors.pink),
  (value: 'primary',   label: 'Ensino Primário',       icon: Icons.menu_book_outlined,     color: Colors.blue),
  (value: 'secondary', label: 'Ensino Secundário',     icon: Icons.school_outlined,        color: Colors.indigo),
  (value: 'combined',  label: 'Primário + Secundário', icon: Icons.account_balance_outlined, color: Colors.teal),
  (value: 'full',      label: 'Escola Completa',       icon: Icons.domain_outlined,        color: Colors.deepPurple),
];

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final _schoolDetailProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>(
  (ref, id) async {
    final data = await ref.read(apiClientProvider).get('/platform/schools/$id');
    return data as Map<String, dynamic>;
  },
);

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class SchoolConfigScreen extends ConsumerStatefulWidget {
  final String schoolId;
  final String schoolName;

  const SchoolConfigScreen({
    super.key,
    required this.schoolId,
    required this.schoolName,
  });

  @override
  ConsumerState<SchoolConfigScreen> createState() => _SchoolConfigScreenState();
}

class _SchoolConfigScreenState extends ConsumerState<SchoolConfigScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  String _segment = 'preschool';
  // Feature overrides: null = follow segment default, bool = explicit value
  final Map<String, bool?> _featureOverrides = {};
  // Role permission overrides: role → feature → bool (false = denied)
  final Map<String, Map<String, bool>> _rolePerms = {};
  bool _saving = false;
  String? _error;
  bool _initialised = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _initFromSchool(Map<String, dynamic> school) {
    if (_initialised) return;
    _initialised = true;
    _segment = school['segment'] as String? ?? 'preschool';
    final raw = school['features'] as Map<String, dynamic>? ?? {};
    for (final entry in raw.entries) {
      if (entry.key == 'role_permissions') {
        final rp = entry.value;
        if (rp is Map) {
          for (final roleEntry in rp.entries) {
            final roleMap = roleEntry.value;
            if (roleMap is Map) {
              _rolePerms[roleEntry.key.toString()] = {
                for (final e in roleMap.entries)
                  if (e.value is bool) e.key.toString(): e.value as bool,
              };
            }
          }
        }
      } else if (entry.value is bool) {
        _featureOverrides[entry.key] = entry.value as bool;
      }
    }
  }

  bool _effectiveFeat(String key) {
    if (_featureOverrides.containsKey(key)) return _featureOverrides[key]!;
    return (_segmentDefaults[_segment] ?? {})[key] ?? true;
  }

  bool _isOverridden(String key) {
    if (!_featureOverrides.containsKey(key)) return false;
    final def = (_segmentDefaults[_segment] ?? {})[key] ?? true;
    return _featureOverrides[key] != def;
  }

  void _toggleFeat(String key, bool value) {
    setState(() {
      final def = (_segmentDefaults[_segment] ?? {})[key] ?? true;
      if (value == def) {
        _featureOverrides.remove(key);
      } else {
        _featureOverrides[key] = value;
      }
    });
  }

  void _changeSegment(String seg) {
    setState(() {
      _segment = seg;
      _featureOverrides.removeWhere((k, v) {
        final def = (_segmentDefaults[seg] ?? {})[k] ?? true;
        return v == def;
      });
    });
  }

  // Role permissions — default access derived from role's defaultFeatures list
  bool _roleDefault(String roleKey, String featureKey) {
    final role = kConfigRoles.where((r) => r.key == roleKey).firstOrNull;
    return role?.defaultFeatures.contains(featureKey) ?? true;
  }

  bool _roleCanAccess(String roleKey, String featureKey) =>
      _rolePerms[roleKey]?[featureKey] ?? _roleDefault(roleKey, featureKey);

  bool _isRolePermOverridden(String roleKey, String featureKey) =>
      _rolePerms[roleKey]?.containsKey(featureKey) ?? false;

  void _toggleRolePerm(String roleKey, String featureKey, bool value) {
    setState(() {
      final def = _roleDefault(roleKey, featureKey);
      if (value == def) {
        // Matches default — remove explicit override (clean slate)
        _rolePerms[roleKey]?.remove(featureKey);
        if (_rolePerms[roleKey]?.isEmpty ?? false) _rolePerms.remove(roleKey);
      } else {
        // Differs from default — store explicit override (true to grant, false to deny)
        _rolePerms.putIfAbsent(roleKey, () => {})[featureKey] = value;
      }
    });
  }

  Future<void> _save() async {
    setState(() { _saving = true; _error = null; });
    try {
      // Build feature overrides dict — only include keys that differ from segment default.
      // Sending null values would corrupt resolved_features (null overrides the default).
      final featOverrides = <String, dynamic>{};
      for (final f in _allFeatures) {
        final def = (_segmentDefaults[_segment] ?? {})[f.key] ?? true;
        final eff = _effectiveFeat(f.key);
        if (eff != def) featOverrides[f.key] = eff;
      }
      // Add role_permissions
      if (_rolePerms.isNotEmpty) {
        featOverrides['role_permissions'] = {
          for (final e in _rolePerms.entries)
            if (e.value.isNotEmpty) e.key: e.value,
        };
      } else {
        featOverrides['role_permissions'] = null; // clear
      }

      await ref.read(apiClientProvider).patch(
        '/platform/schools/${widget.schoolId}',
        data: {'segment': _segment, 'features': featOverrides},
      );

      ref.invalidate(_schoolDetailProvider(widget.schoolId));
      ref.invalidate(schoolInfoProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Configuração guardada'),
          backgroundColor: Colors.green,
        ));
      }
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_schoolDetailProvider(widget.schoolId));
    return async.when(
      loading: () => Scaffold(appBar: AppBar(title: Text(widget.schoolName)),
          body: const Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(appBar: AppBar(title: Text(widget.schoolName)),
          body: Center(child: Text('Erro: $e'))),
      data: (school) {
        _initFromSchool(school);
        return Scaffold(
          appBar: AppBar(
            title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.schoolName),
              const Text('Configuração da Escola',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w400)),
            ]),
            bottom: TabBar(
              controller: _tabs,
              tabs: const [
                Tab(icon: Icon(Icons.tune, size: 18), text: 'Funcionalidades'),
                Tab(icon: Icon(Icons.people_outline, size: 18), text: 'Permissões por Função'),
              ],
            ),
            actions: [
              if (_saving)
                const Padding(padding: EdgeInsets.all(16),
                    child: SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2)))
              else
                FilledButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.save_outlined, size: 18),
                  label: const Text('Guardar'),
                ),
              const SizedBox(width: 8),
            ],
          ),
          body: TabBarView(
            controller: _tabs,
            children: [
              _FeaturesTab(
                segment: _segment,
                onSegmentChange: _changeSegment,
                error: _error,
                effectiveFeat: _effectiveFeat,
                isOverridden: _isOverridden,
                toggleFeat: _toggleFeat,
              ),
              _RolePermsTab(
                enabledFeatures: {
                  for (final f in _allFeatures)
                    if (_effectiveFeat(f.key)) f.key,
                },
                roleCanAccess: _roleCanAccess,
                isRolePermOverridden: _isRolePermOverridden,
                toggleRolePerm: _toggleRolePerm,
              ),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Tab 1: Features
// ---------------------------------------------------------------------------

class _FeaturesTab extends StatelessWidget {
  final String segment;
  final ValueChanged<String> onSegmentChange;
  final String? error;
  final bool Function(String) effectiveFeat;
  final bool Function(String) isOverridden;
  final void Function(String, bool) toggleFeat;

  const _FeaturesTab({
    required this.segment,
    required this.onSegmentChange,
    required this.error,
    required this.effectiveFeat,
    required this.isOverridden,
    required this.toggleFeat,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 80),
      children: [
        if (error != null) ...[
          _ErrorBanner(message: error!),
          const SizedBox(height: 16),
        ],

        // Segment selector
        _SectionHeader(icon: Icons.category_outlined, label: 'Tipo de Escola',
            subtitle: 'Define os valores predefinidos para todas as funcionalidades'),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8, runSpacing: 8,
          children: _segments.map((seg) {
            final sel = segment == seg.value;
            return GestureDetector(
              onTap: () => onSegmentChange(seg.value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: sel ? seg.color.withOpacity(0.12) : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: sel ? seg.color : Colors.grey.shade300, width: sel ? 2 : 1),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(seg.icon, size: 18, color: sel ? seg.color : Colors.grey.shade600),
                  const SizedBox(width: 8),
                  Text(seg.label, style: TextStyle(fontSize: 13,
                      fontWeight: sel ? FontWeight.w700 : FontWeight.normal,
                      color: sel ? seg.color : null)),
                  if (sel) ...[const SizedBox(width: 6),
                    Icon(Icons.check_circle, size: 16, color: seg.color)],
                ]),
              ),
            );
          }).toList(),
        ),

        const SizedBox(height: 24),
        const Divider(),

        // Feature categories
        for (final cat in _Cat.values) ...[
          const SizedBox(height: 20),
          _SectionHeader(icon: _catIcons[cat]!, label: _catLabels[cat]!),
          const SizedBox(height: 8),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.grey.shade200),
            ),
            child: Column(
              children: _allFeatures.where((f) => f.cat == cat).map((f) {
                final val = effectiveFeat(f.key);
                final overridden = isOverridden(f.key);
                final def = (_segmentDefaults[segment] ?? {})[f.key] ?? true;
                return ListTile(
                  leading: Icon(f.icon, color: val ? AppTheme.primary : Colors.grey.shade400, size: 22),
                  title: Row(children: [
                    Expanded(child: Text(f.label, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14))),
                    const SizedBox(width: 8),
                    _StatusChip(overridden: overridden, defaultValue: def),
                  ]),
                  subtitle: Text(f.description, style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                  trailing: Switch(value: val, onChanged: (v) => toggleFeat(f.key, v)),
                );
              }).toList(),
            ),
          ),
        ],

        const SizedBox(height: 24),
        Row(children: [
          _LegendChip(color: Colors.blue, label: 'Valor predefinido pelo tipo de escola'),
          const SizedBox(width: 16),
          _LegendChip(color: Colors.orange, label: 'Valor personalizado'),
        ]),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Tab 2: Role Permissions
// ---------------------------------------------------------------------------

class _RolePermsTab extends StatelessWidget {
  final Set<String> enabledFeatures;
  final bool Function(String role, String feat) roleCanAccess;
  final bool Function(String role, String feat) isRolePermOverridden;
  final void Function(String role, String feat, bool val) toggleRolePerm;

  const _RolePermsTab({
    required this.enabledFeatures,
    required this.roleCanAccess,
    required this.isRolePermOverridden,
    required this.toggleRolePerm,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 80),
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.blue.withOpacity(0.2)),
          ),
          child: const Row(children: [
            Icon(Icons.info_outline, size: 18, color: Colors.blue),
            SizedBox(width: 8),
            Expanded(child: Text(
              'Cada função tem um conjunto predefinido de funcionalidades. '
              'Use os controlos abaixo para conceder acesso a funcionalidades extra ou restringir funcionalidades predefinidas, por função e por escola.',
              style: TextStyle(fontSize: 12, color: Colors.blue),
            )),
          ]),
        ),
        const SizedBox(height: 16),

        for (final role in kConfigRoles) ...[
          const SizedBox(height: 8),
          _RolePermCard(
            role: role,
            enabledFeatures: enabledFeatures,
            roleCanAccess: roleCanAccess,
            isOverridden: isRolePermOverridden,
            onToggle: toggleRolePerm,
          ),
        ],
      ],
    );
  }
}

class _RolePermCard extends StatefulWidget {
  final RoleDef role;
  final Set<String> enabledFeatures;
  final bool Function(String, String) roleCanAccess;
  final bool Function(String, String) isOverridden;
  final void Function(String, String, bool) onToggle;

  const _RolePermCard({
    required this.role,
    required this.enabledFeatures,
    required this.roleCanAccess,
    required this.isOverridden,
    required this.onToggle,
  });

  @override
  State<_RolePermCard> createState() => _RolePermCardState();
}

class _RolePermCardState extends State<_RolePermCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final allFeats = widget.enabledFeatures.toList()
      ..sort((a, b) {
        // Default-ON features first, then extras
        final aDefault = widget.role.defaultFeatures.contains(a);
        final bDefault = widget.role.defaultFeatures.contains(b);
        if (aDefault == bDefault) return a.compareTo(b);
        return aDefault ? -1 : 1;
      });

    final deniedCount = allFeats
        .where((f) => widget.role.defaultFeatures.contains(f) &&
            !widget.roleCanAccess(widget.role.key, f))
        .length;
    final grantedExtras = allFeats
        .where((f) => !widget.role.defaultFeatures.contains(f) &&
            widget.roleCanAccess(widget.role.key, f))
        .length;
    final hasOverrides = deniedCount > 0 || grantedExtras > 0;

    String subtitle;
    Color subtitleColor;
    if (deniedCount > 0 && grantedExtras > 0) {
      subtitle = '$deniedCount restrição(ões) · $grantedExtras extra(s) concedido(s)';
      subtitleColor = Colors.orange;
    } else if (deniedCount > 0) {
      subtitle = '$deniedCount restrição(ões) activa(s)';
      subtitleColor = Colors.orange;
    } else if (grantedExtras > 0) {
      subtitle = '$grantedExtras funcionalidade(s) extra concedida(s)';
      subtitleColor = Colors.blue;
    } else {
      subtitle = 'Acesso predefinido a ${widget.role.defaultFeatures.where(widget.enabledFeatures.contains).length} funcionalidade(s)';
      subtitleColor = AppTheme.textSecondary;
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: hasOverrides
              ? widget.role.color.withOpacity(0.35)
              : Colors.grey.shade200,
          width: hasOverrides ? 1.5 : 1,
        ),
      ),
      child: Column(children: [
        InkWell(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: widget.role.color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(widget.role.icon, color: widget.role.color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(widget.role.label,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                Text(subtitle,
                    style: TextStyle(fontSize: 12, color: subtitleColor,
                        fontWeight: hasOverrides ? FontWeight.w600 : FontWeight.normal)),
              ])),
              Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                  color: Colors.grey.shade500),
            ]),
          ),
        ),
        if (_expanded) ...[
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // ── Default features ──────────────────────────────────────────
              if (allFeats.any(widget.role.defaultFeatures.contains)) ...[
                _PermSection(
                  label: 'Acesso por defeito',
                  subtitle: 'Activo para esta função salvo restrição explícita',
                  color: Colors.green,
                  icon: Icons.check_circle_outline,
                  features: allFeats.where(widget.role.defaultFeatures.contains).toList(),
                  roleKey: widget.role.key,
                  roleCanAccess: widget.roleCanAccess,
                  isOverridden: widget.isOverridden,
                  onToggle: widget.onToggle,
                ),
                const SizedBox(height: 16),
              ],
              // ── Extra features (not in defaults) ─────────────────────────
              if (allFeats.any((f) => !widget.role.defaultFeatures.contains(f))) ...[
                _PermSection(
                  label: 'Funcionalidades adicionais',
                  subtitle: 'Inactivo por defeito — active para conceder acesso extra',
                  color: Colors.blue,
                  icon: Icons.add_circle_outline,
                  features: allFeats.where((f) => !widget.role.defaultFeatures.contains(f)).toList(),
                  roleKey: widget.role.key,
                  roleCanAccess: widget.roleCanAccess,
                  isOverridden: widget.isOverridden,
                  onToggle: widget.onToggle,
                ),
              ],
              if (allFeats.isEmpty)
                Text('Nenhuma funcionalidade activa nesta escola.',
                    style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
            ]),
          ),
        ],
      ]),
    );
  }
}

class _PermSection extends StatelessWidget {
  final String label;
  final String subtitle;
  final Color color;
  final IconData icon;
  final List<String> features;
  final String roleKey;
  final bool Function(String, String) roleCanAccess;
  final bool Function(String, String) isOverridden;
  final void Function(String, String, bool) onToggle;

  const _PermSection({
    required this.label,
    required this.subtitle,
    required this.color,
    required this.icon,
    required this.features,
    required this.roleKey,
    required this.roleCanAccess,
    required this.isOverridden,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
      ]),
      const SizedBox(height: 2),
      Text(subtitle,
          style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
      const SizedBox(height: 8),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: features.map((f) {
          final allowed = roleCanAccess(roleKey, f);
          final overridden = isOverridden(roleKey, f);
          return FilterChip(
            visualDensity: VisualDensity.compact,
            label: Text(_featLabel[f] ?? f,
                style: TextStyle(
                  fontSize: 12,
                  color: allowed ? null : Colors.red.shade700,
                  decoration: allowed ? null : TextDecoration.lineThrough,
                  fontWeight: overridden ? FontWeight.w600 : FontWeight.normal,
                )),
            selected: allowed,
            selectedColor: overridden
                ? color.withOpacity(0.15)
                : color.withOpacity(0.10),
            checkmarkColor: color,
            onSelected: (v) => onToggle(roleKey, f, v),
            side: BorderSide(
              color: allowed
                  ? (overridden ? color.withOpacity(0.6) : color.withOpacity(0.3))
                  : Colors.red.withOpacity(0.4),
            ),
          );
        }).toList(),
      ),
    ]);
  }
}

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  const _SectionHeader({required this.icon, required this.label, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, size: 20, color: AppTheme.primary),
      const SizedBox(width: 8),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        if (subtitle != null)
          Text(subtitle!, style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
      ]),
    ]);
  }
}

class _StatusChip extends StatelessWidget {
  final bool overridden;
  final bool defaultValue;
  const _StatusChip({required this.overridden, required this.defaultValue});

  @override
  Widget build(BuildContext context) {
    if (overridden) {
      return _chip('personalizado', Colors.orange);
    }
    return _chip(defaultValue ? 'activo por defeito' : 'inactivo por defeito',
        defaultValue ? Colors.blue : Colors.grey.shade500);
  }

  Widget _chip(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: color.withOpacity(0.1),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: color.withOpacity(0.3)),
    ),
    child: Text(text, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
  );
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.danger.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.danger.withOpacity(0.3)),
      ),
      child: Row(children: [
        Icon(Icons.error_outline, color: AppTheme.danger, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(message, style: TextStyle(color: AppTheme.danger, fontSize: 13))),
      ]),
    );
  }
}

class _LegendChip extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendChip({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 10, height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 6),
      Text(label, style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
    ]);
  }
}
