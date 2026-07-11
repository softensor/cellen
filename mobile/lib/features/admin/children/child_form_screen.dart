import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_client.dart';
import '../../../core/models/child.dart';
import 'child_detail_screen.dart' show childProvider;
import 'children_list_screen.dart' show childrenProvider;

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------
class ChildFormScreen extends ConsumerStatefulWidget {
  final String? childId;
  const ChildFormScreen({super.key, this.childId});

  @override
  ConsumerState<ChildFormScreen> createState() => _ChildFormScreenState();
}

class _ChildFormScreenState extends ConsumerState<ChildFormScreen> {
  final _formKey = GlobalKey<FormState>();

  // Controllers
  final _firstNameCtrl = TextEditingController();
  final _middleNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _cedulaCtrl = TextEditingController();
  final _specialNeedsCtrl = TextEditingController();
  final _medicalCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _postalCtrl = TextEditingController();

  DateTime? _birthDate;
  String? _sex;
  bool _isLoading = false;
  bool _isLoadingChild = false;
  String? _error;
  bool _addressExpanded = false;

  bool get isEditing => widget.childId != null;

  @override
  void initState() {
    super.initState();
    if (isEditing) {
      _loadChild();
    }
  }

  Future<void> _loadChild() async {
    setState(() => _isLoadingChild = true);
    try {
      final api = ref.read(apiClientProvider);
      final data = await api.get('/children/${widget.childId}');
      final child = Child.fromJson(data as Map<String, dynamic>);
      _firstNameCtrl.text = child.firstName;
      _middleNameCtrl.text = child.middleName ?? '';
      _lastNameCtrl.text = child.lastName;
      _cedulaCtrl.text = child.cedula;
      _specialNeedsCtrl.text = child.specialNeeds ?? '';
      _medicalCtrl.text = child.medicalPrescription ?? '';
      _addressCtrl.text = child.address ?? '';
      _cityCtrl.text = child.addressCity ?? '';
      _postalCtrl.text = child.addressPostalCode ?? '';
      setState(() {
        _birthDate = child.birthDate;
        _sex = child.sex;
        _isLoadingChild = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoadingChild = false;
      });
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime(DateTime.now().year - 3),
      firstDate: DateTime(DateTime.now().year - 18),
      lastDate: DateTime.now(),
      locale: const Locale('pt', 'PT'),
    );
    if (picked != null) {
      setState(() => _birthDate = picked);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final body = <String, dynamic>{
      'first_name': _firstNameCtrl.text.trim(),
      'last_name': _lastNameCtrl.text.trim(),
      'cedula': _cedulaCtrl.text.trim(),
    };
    if (_middleNameCtrl.text.trim().isNotEmpty) {
      body['middle_name'] = _middleNameCtrl.text.trim();
    }
    if (_birthDate != null) {
      body['birth_date'] =
          '${_birthDate!.year.toString().padLeft(4, '0')}-${_birthDate!.month.toString().padLeft(2, '0')}-${_birthDate!.day.toString().padLeft(2, '0')}';
    }
    if (_sex != null) body['sex'] = _sex;
    if (_specialNeedsCtrl.text.trim().isNotEmpty) {
      body['special_needs'] = _specialNeedsCtrl.text.trim();
    }
    if (_medicalCtrl.text.trim().isNotEmpty) {
      body['medical_prescription'] = _medicalCtrl.text.trim();
    }
    if (_addressCtrl.text.trim().isNotEmpty) {
      body['address'] = _addressCtrl.text.trim();
    }
    if (_cityCtrl.text.trim().isNotEmpty) {
      body['address_city'] = _cityCtrl.text.trim();
    }
    if (_postalCtrl.text.trim().isNotEmpty) {
      body['address_postal_code'] = _postalCtrl.text.trim();
    }

    try {
      final api = ref.read(apiClientProvider);
      if (isEditing) {
        await api.patch('/children/${widget.childId}', data: body);
        ref.invalidate(childProvider(widget.childId!));
      } else {
        await api.post('/children', data: body);
      }
      ref.invalidate(childrenProvider);
      if (mounted) context.pop();
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _middleNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _cedulaCtrl.dispose();
    _specialNeedsCtrl.dispose();
    _medicalCtrl.dispose();
    _addressCtrl.dispose();
    _cityCtrl.dispose();
    _postalCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingChild) {
      return Scaffold(
        appBar: AppBar(
            title: Text(isEditing ? 'Editar Criança' : 'Nova Criança')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Editar Criança' : 'Nova Criança'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sectionHeader(context, 'Identificação'),
              const SizedBox(height: 12),

              TextFormField(
                controller: _firstNameCtrl,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Primeiro Nome *',
                  prefixIcon: Icon(Icons.person),
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Campo obrigatório' : null,
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _middleNameCtrl,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Nome do Meio',
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _lastNameCtrl,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Apelido *',
                  prefixIcon: Icon(Icons.person),
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Campo obrigatório' : null,
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _cedulaCtrl,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Cédula / BI *',
                  prefixIcon: Icon(Icons.badge),
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Campo obrigatório' : null,
              ),
              const SizedBox(height: 16),

              // Birth date
              InkWell(
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(8),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Data de Nascimento',
                    prefixIcon: Icon(Icons.cake),
                  ),
                  child: Text(
                    _birthDate != null
                        ? DateFormat('dd/MM/yyyy').format(_birthDate!)
                        : 'Seleccionar data',
                    style: _birthDate == null
                        ? TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant)
                        : null,
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Sex
              DropdownButtonFormField<String>(
                value: _sex,
                decoration: const InputDecoration(
                  labelText: 'Sexo',
                  prefixIcon: Icon(Icons.wc),
                ),
                items: const [
                  DropdownMenuItem(value: 'M', child: Text('Masculino')),
                  DropdownMenuItem(value: 'F', child: Text('Feminino')),
                ],
                onChanged: (v) => setState(() => _sex = v),
              ),
              const SizedBox(height: 24),

              _sectionHeader(context, 'Saúde'),
              const SizedBox(height: 12),

              TextFormField(
                controller: _specialNeedsCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Necessidades Especiais',
                  prefixIcon: Icon(Icons.accessibility_new),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _medicalCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Prescrição Médica',
                  prefixIcon: Icon(Icons.medical_services),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 24),

              // Expandable address section
              InkWell(
                onTap: () =>
                    setState(() => _addressExpanded = !_addressExpanded),
                borderRadius: BorderRadius.circular(8),
                child: Row(
                  children: [
                    _sectionHeader(context, 'Morada', expand: false),
                    const Spacer(),
                    Icon(_addressExpanded
                        ? Icons.expand_less
                        : Icons.expand_more),
                  ],
                ),
              ),

              if (_addressExpanded) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _addressCtrl,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Endereço',
                    prefixIcon: Icon(Icons.home),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _cityCtrl,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Cidade',
                    prefixIcon: Icon(Icons.location_city),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _postalCtrl,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: 'Código Postal',
                    prefixIcon: Icon(Icons.local_post_office),
                  ),
                ),
              ],

              if (_error != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _error!,
                    style: TextStyle(
                        color: Theme.of(context)
                            .colorScheme
                            .onErrorContainer),
                  ),
                ),
              ],

              const SizedBox(height: 32),

              FilledButton(
                onPressed: _isLoading ? null : _submit,
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : Text(isEditing ? 'Guardar Alterações' : 'Criar Criança'),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String text, {bool expand = true}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }
}
