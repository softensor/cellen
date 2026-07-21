import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';

// ---------------------------------------------------------------------------
// Segment metadata
// ---------------------------------------------------------------------------

const _segments = [
  (
    value: 'preschool',
    label: 'Pré-Escolar',
    description: 'Berçário, Creche, Jardim de Infância',
    icon: Icons.child_care_outlined,
    color: Colors.pink,
  ),
  (
    value: 'primary',
    label: 'Ensino Primário',
    description: '1ª – 6ª Classe',
    icon: Icons.menu_book_outlined,
    color: Colors.blue,
  ),
  (
    value: 'secondary',
    label: 'Ensino Secundário',
    description: '7ª – 12ª Classe',
    icon: Icons.school_outlined,
    color: Colors.indigo,
  ),
  (
    value: 'combined',
    label: 'Primário + Secundário',
    description: '1ª – 12ª Classe',
    icon: Icons.account_balance_outlined,
    color: Colors.teal,
  ),
  (
    value: 'full',
    label: 'Escola Completa',
    description: 'Pré-Escolar + Primário + Secundário',
    icon: Icons.domain_outlined,
    color: Colors.deepPurple,
  ),
];

String _segmentLabel(String value) =>
    _segments.firstWhere((s) => s.value == value, orElse: () => _segments.first).label;

Color _segmentColor(String value) =>
    _segments.firstWhere((s) => s.value == value, orElse: () => _segments.first).color;

IconData _segmentIcon(String value) =>
    _segments.firstWhere((s) => s.value == value, orElse: () => _segments.first).icon;

// ---------------------------------------------------------------------------
// Schools Screen
// ---------------------------------------------------------------------------

class SchoolsScreen extends ConsumerStatefulWidget {
  const SchoolsScreen({super.key});

  @override
  ConsumerState<SchoolsScreen> createState() => _SchoolsScreenState();
}

class _SchoolsScreenState extends ConsumerState<SchoolsScreen> {
  List<Map<String, dynamic>> _schools = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      final data = await api.get('/platform/schools');
      setState(() {
        _schools = (data as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _loading = false;
      });
    } on ApiException catch (e) {
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  Future<void> _toggleActive(String id, bool current) async {
    try {
      final api = ref.read(apiClientProvider);
      await api.post('/platform/schools/$id/activate', data: {});
      await _load();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _showCreateDialog() async {
    await showDialog(
      useRootNavigator: false,
      context: context,
      barrierDismissible: false,
      builder: (_) => _CreateSchoolDialog(
        onCreated: _load,
        apiClient: ref.read(apiClientProvider),
      ),
    );
  }

  Future<void> _showEditDialog(Map<String, dynamic> school) async {
    await showDialog(
      useRootNavigator: false,
      context: context,
      barrierDismissible: false,
      builder: (_) => _EditSchoolDialog(
        school: school,
        onUpdated: _load,
        apiClient: ref.read(apiClientProvider),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gerir Escolas'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateDialog,
        icon: const Icon(Icons.add),
        label: const Text('Nova Escola'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline,
                          color: Theme.of(context).colorScheme.error,
                          size: 48),
                      const SizedBox(height: 8),
                      Text(_error!),
                      TextButton(
                        onPressed: _load,
                        child: const Text('Tentar novamente'),
                      ),
                    ],
                  ),
                )
              : _schools.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.school_outlined,
                              size: 64, color: Colors.grey),
                          const SizedBox(height: 16),
                          const Text('Nenhuma escola registada'),
                          const SizedBox(height: 8),
                          ElevatedButton.icon(
                            onPressed: _showCreateDialog,
                            icon: const Icon(Icons.add),
                            label: const Text('Criar primeira escola'),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                        itemCount: _schools.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final s = _schools[i];
                          final isActive = s['is_active'] as bool? ?? false;
                          final segment = s['segment'] as String? ?? 'preschool';
                          final segColor = _segmentColor(segment);
                          return Card(
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: isActive
                                    ? segColor.withAlpha(40)
                                    : Colors.grey.shade200,
                                child: Icon(
                                  _segmentIcon(segment),
                                  color: isActive ? segColor : Colors.grey,
                                ),
                              ),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(s['name'] as String? ?? ''),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: segColor.withAlpha(30),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                          color: segColor.withAlpha(80)),
                                    ),
                                    child: Text(
                                      _segmentLabel(segment),
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: segColor,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Slug: ${s['slug'] ?? ''}'),
                                  if (s['city'] != null)
                                    Text(s['city'] as String),
                                  Text(
                                    '${s['active_users_count'] ?? 0} utilizadores · '
                                    '${s['children_count'] ?? 0} alunos',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ],
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit_outlined),
                                    tooltip: 'Editar',
                                    onPressed: () => _showEditDialog(s),
                                  ),
                                  Switch(
                                    value: isActive,
                                    onChanged: (_) =>
                                        _toggleActive(s['id'] as String, isActive),
                                  ),
                                ],
                              ),
                              isThreeLine: true,
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}

// ---------------------------------------------------------------------------
// Segment Selector widget (shared)
// ---------------------------------------------------------------------------

class _SegmentSelector extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;

  const _SegmentSelector({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Tipo de Escola *',
            style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _segments.map((seg) {
            final isSelected = selected == seg.value;
            return GestureDetector(
              onTap: () => onChanged(seg.value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected
                      ? seg.color.withAlpha(30)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected ? seg.color : Colors.grey.shade300,
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(seg.icon,
                        size: 18,
                        color: isSelected ? seg.color : Colors.grey.shade600),
                    const SizedBox(width: 6),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          seg.label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: isSelected ? seg.color : null,
                          ),
                        ),
                        Text(
                          seg.description,
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                    if (isSelected) ...[
                      const SizedBox(width: 6),
                      Icon(Icons.check_circle, size: 16, color: seg.color),
                    ],
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Create School Dialog
// ---------------------------------------------------------------------------

class _CreateSchoolDialog extends StatefulWidget {
  final VoidCallback onCreated;
  final ApiClient apiClient;

  const _CreateSchoolDialog({
    required this.onCreated,
    required this.apiClient,
  });

  @override
  State<_CreateSchoolDialog> createState() => _CreateSchoolDialogState();
}

class _CreateSchoolDialogState extends State<_CreateSchoolDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _slugCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _countryCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _adminUsernameCtrl = TextEditingController();
  final _adminPasswordCtrl = TextEditingController();
  String _segment = 'preschool';
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _slugCtrl.dispose();
    _cityCtrl.dispose();
    _countryCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _adminUsernameCtrl.dispose();
    _adminPasswordCtrl.dispose();
    super.dispose();
  }

  void _autoSlug(String name) {
    final slug = name
        .toLowerCase()
        .replaceAll(RegExp(r'[àáâãä]'), 'a')
        .replaceAll(RegExp(r'[èéêë]'), 'e')
        .replaceAll(RegExp(r'[ìíîï]'), 'i')
        .replaceAll(RegExp(r'[òóôõö]'), 'o')
        .replaceAll(RegExp(r'[ùúûü]'), 'u')
        .replaceAll(RegExp(r'[ç]'), 'c')
        .replaceAll(RegExp(r'[^a-z0-9\s-]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '-');
    _slugCtrl.text = slug;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.apiClient.post('/platform/schools', data: {
        'name': _nameCtrl.text.trim(),
        'slug': _slugCtrl.text.trim(),
        'city': _cityCtrl.text.trim().isEmpty ? null : _cityCtrl.text.trim(),
        'country':
            _countryCtrl.text.trim().isEmpty ? null : _countryCtrl.text.trim(),
        'email':
            _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
        'phone':
            _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
        'admin_username': _adminUsernameCtrl.text.trim(),
        'admin_password': _adminPasswordCtrl.text,
        'segment': _segment,
      });
      if (mounted) Navigator.of(context).pop();
      widget.onCreated();
    } on ApiException catch (e) {
      setState(() {
        _error = e.message;
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nova Escola'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_error != null) ...[
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(_error!,
                        style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onErrorContainer)),
                  ),
                  const SizedBox(height: 12),
                ],
                // Segment selector — first, most important
                _SegmentSelector(
                  selected: _segment,
                  onChanged: (v) => setState(() => _segment = v),
                ),
                const SizedBox(height: 20),
                const Divider(),
                const SizedBox(height: 8),
                Text('Dados da Escola',
                    style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(labelText: 'Nome *'),
                  onChanged: _autoSlug,
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Obrigatório' : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _slugCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Identificador (slug) *',
                    helperText: 'Usado no login. Ex: escola-jardim',
                  ),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Obrigatório' : null,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _cityCtrl,
                        decoration: const InputDecoration(labelText: 'Cidade'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: _countryCtrl,
                        decoration: const InputDecoration(labelText: 'País'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _emailCtrl,
                  decoration: const InputDecoration(labelText: 'Email'),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _phoneCtrl,
                  decoration: const InputDecoration(labelText: 'Telefone'),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),
                Text('Conta de Administrador',
                    style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _adminUsernameCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Utilizador admin *'),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Obrigatório' : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _adminPasswordCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Palavra-passe admin *'),
                  obscureText: true,
                  validator: (v) => v == null || v.length < 6
                      ? 'Mínimo 6 caracteres'
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Criar Escola'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Edit School Dialog
// ---------------------------------------------------------------------------

class _EditSchoolDialog extends StatefulWidget {
  final Map<String, dynamic> school;
  final VoidCallback onUpdated;
  final ApiClient apiClient;

  const _EditSchoolDialog({
    required this.school,
    required this.onUpdated,
    required this.apiClient,
  });

  @override
  State<_EditSchoolDialog> createState() => _EditSchoolDialogState();
}

class _EditSchoolDialogState extends State<_EditSchoolDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _cityCtrl;
  late final TextEditingController _countryCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _nifCtrl;
  late String _segment;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final s = widget.school;
    _nameCtrl = TextEditingController(text: s['name'] as String? ?? '');
    _cityCtrl = TextEditingController(text: s['city'] as String? ?? '');
    _countryCtrl = TextEditingController(text: s['country'] as String? ?? '');
    _emailCtrl = TextEditingController(text: s['email'] as String? ?? '');
    _phoneCtrl = TextEditingController(text: s['phone'] as String? ?? '');
    _nifCtrl = TextEditingController(text: s['nif'] as String? ?? '');
    _segment = s['segment'] as String? ?? 'preschool';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _cityCtrl.dispose();
    _countryCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _nifCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final id = widget.school['id'] as String;
      await widget.apiClient.patch('/platform/schools/$id', data: {
        'name': _nameCtrl.text.trim(),
        'city': _cityCtrl.text.trim().isEmpty ? null : _cityCtrl.text.trim(),
        'country': _countryCtrl.text.trim().isEmpty ? null : _countryCtrl.text.trim(),
        'email': _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
        'nif': _nifCtrl.text.trim().isEmpty ? null : _nifCtrl.text.trim(),
        'segment': _segment,
      });
      if (mounted) Navigator.of(context).pop();
      widget.onUpdated();
    } on ApiException catch (e) {
      setState(() {
        _error = e.message;
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Editar Escola'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_error != null) ...[
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(_error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.onErrorContainer)),
                  ),
                  const SizedBox(height: 12),
                ],
                _SegmentSelector(
                  selected: _segment,
                  onChanged: (v) => setState(() => _segment = v),
                ),
                const SizedBox(height: 20),
                const Divider(),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(labelText: 'Nome *'),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Obrigatório' : null,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _cityCtrl,
                        decoration: const InputDecoration(labelText: 'Cidade'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: _countryCtrl,
                        decoration: const InputDecoration(labelText: 'País'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _emailCtrl,
                  decoration: const InputDecoration(labelText: 'Email'),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _phoneCtrl,
                  decoration: const InputDecoration(labelText: 'Telefone'),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _nifCtrl,
                  decoration: const InputDecoration(labelText: 'NIF'),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Guardar'),
        ),
      ],
    );
  }
}
