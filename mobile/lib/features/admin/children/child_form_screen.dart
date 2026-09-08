import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_client.dart';
import '../../../core/models/child.dart';
import '../../../core/models/school_terms.dart';
import '../../../core/providers/currency_provider.dart';
import 'child_detail_screen.dart' show childProvider;
import 'children_list_screen.dart' show childrenProvider;

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------
class ChildFormScreen extends ConsumerStatefulWidget {
  final String? childId;
  final ValueChanged<Map<String, dynamic>>? onCreated;
  const ChildFormScreen({super.key, this.childId, this.onCreated});

  @override
  ConsumerState<ChildFormScreen> createState() => _ChildFormScreenState();
}

class _ChildFormScreenState extends ConsumerState<ChildFormScreen> {
  final _formKey = GlobalKey<FormState>();

  // Identity
  final _firstNameCtrl = TextEditingController();
  final _middleNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _cedulaCtrl = TextEditingController();
  final _placeOfBirthCtrl = TextEditingController();
  final _nationalityCtrl = TextEditingController();
  final _heightCtrl = TextEditingController();

  // Health
  final _specialNeedsCtrl = TextEditingController();
  final _medicalCtrl = TextEditingController();

  // Address
  final _streetCtrl = TextEditingController();
  final _houseNumberCtrl = TextEditingController();
  final _buildingCtrl = TextEditingController();
  final _aptCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _municipioCtrl = TextEditingController();
  final _bairroCtrl = TextEditingController();

  // Emergency contact
  final _emergencyNameCtrl = TextEditingController();
  final _emergencyPhoneCtrl = TextEditingController();

  DateTime? _birthDate;
  String? _sex;
  bool _isLoading = false;
  bool _isLoadingChild = false;
  String? _error;
  bool _addressExpanded = false;
  bool _emergencyExpanded = false;

  bool get isEditing => widget.childId != null;

  @override
  void initState() {
    super.initState();
    if (isEditing) _loadChild();
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
      _placeOfBirthCtrl.text = child.placeOfBirth ?? '';
      _nationalityCtrl.text = child.nationality ?? '';
      _heightCtrl.text = child.height != null ? child.height.toString() : '';
      _specialNeedsCtrl.text = child.specialNeeds ?? '';
      _medicalCtrl.text = child.medicalPrescription ?? '';
      _streetCtrl.text = child.street ?? '';
      _houseNumberCtrl.text = child.houseNumber ?? '';
      _buildingCtrl.text = child.buildingNumber ?? '';
      _aptCtrl.text = child.aptNumber ?? '';
      _cityCtrl.text = child.city ?? '';
      _municipioCtrl.text = child.municipio ?? '';
      _bairroCtrl.text = child.bairro ?? '';
      _emergencyNameCtrl.text = child.emergencyContactName ?? '';
      _emergencyPhoneCtrl.text = child.emergencyContactPhone ?? '';
      setState(() {
        _birthDate = child.birthDate;
        _sex = child.sex;
        _isLoadingChild = false;
        _addressExpanded = child.street != null && child.street!.isNotEmpty;
        _emergencyExpanded = child.emergencyContactName != null && child.emergencyContactName!.isNotEmpty;
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
    if (picked != null) setState(() => _birthDate = picked);
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
    if (_middleNameCtrl.text.trim().isNotEmpty) body['middle_name'] = _middleNameCtrl.text.trim();
    if (_birthDate != null) {
      body['birth_date'] =
          '${_birthDate!.year.toString().padLeft(4, '0')}-${_birthDate!.month.toString().padLeft(2, '0')}-${_birthDate!.day.toString().padLeft(2, '0')}';
    }
    if (_sex != null) body['sex'] = _sex;
    if (_placeOfBirthCtrl.text.trim().isNotEmpty) body['place_of_birth'] = _placeOfBirthCtrl.text.trim();
    if (_nationalityCtrl.text.trim().isNotEmpty) body['nationality'] = _nationalityCtrl.text.trim();
    if (_heightCtrl.text.trim().isNotEmpty) body['height'] = double.tryParse(_heightCtrl.text.trim());
    if (_specialNeedsCtrl.text.trim().isNotEmpty) body['special_needs'] = _specialNeedsCtrl.text.trim();
    if (_medicalCtrl.text.trim().isNotEmpty) body['medical_prescription'] = _medicalCtrl.text.trim();
    // Address
    if (_streetCtrl.text.trim().isNotEmpty) body['street'] = _streetCtrl.text.trim();
    if (_houseNumberCtrl.text.trim().isNotEmpty) body['house_number'] = _houseNumberCtrl.text.trim();
    if (_buildingCtrl.text.trim().isNotEmpty) body['building_number'] = _buildingCtrl.text.trim();
    if (_aptCtrl.text.trim().isNotEmpty) body['apt_number'] = _aptCtrl.text.trim();
    if (_cityCtrl.text.trim().isNotEmpty) body['city'] = _cityCtrl.text.trim();
    if (_municipioCtrl.text.trim().isNotEmpty) body['municipio'] = _municipioCtrl.text.trim();
    if (_bairroCtrl.text.trim().isNotEmpty) body['bairro'] = _bairroCtrl.text.trim();
    // Emergency
    if (_emergencyNameCtrl.text.trim().isNotEmpty) body['emergency_contact_name'] = _emergencyNameCtrl.text.trim();
    if (_emergencyPhoneCtrl.text.trim().isNotEmpty) body['emergency_contact_phone'] = _emergencyPhoneCtrl.text.trim();

    try {
      final api = ref.read(apiClientProvider);
      if (isEditing) {
        await api.patch('/children/${widget.childId}', data: body);
        ref.invalidate(childProvider(widget.childId!));
      } else {
        final created = await api.post('/children', data: body);
        if (!mounted) return;
        ref.invalidate(childrenProvider);
        if (widget.onCreated != null) {
          widget.onCreated!(created as Map<String, dynamic>);
          return;
        }
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
    _placeOfBirthCtrl.dispose();
    _nationalityCtrl.dispose();
    _heightCtrl.dispose();
    _specialNeedsCtrl.dispose();
    _medicalCtrl.dispose();
    _streetCtrl.dispose();
    _houseNumberCtrl.dispose();
    _buildingCtrl.dispose();
    _aptCtrl.dispose();
    _cityCtrl.dispose();
    _municipioCtrl.dispose();
    _bairroCtrl.dispose();
    _emergencyNameCtrl.dispose();
    _emergencyPhoneCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final terms = SchoolTerms.of(ref.watch(schoolInfoProvider).valueOrNull);
    if (_isLoadingChild) {
      return Scaffold(
        appBar: AppBar(title: Text(isEditing ? 'Editar ${terms.student}' : 'Novo ${terms.student}')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(isEditing ? 'Editar ${terms.student}' : 'Novo ${terms.student}')),
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
                decoration: const InputDecoration(labelText: 'Primeiro Nome *', prefixIcon: Icon(Icons.person)),
                validator: (v) => v == null || v.trim().isEmpty ? 'Campo obrigatório' : null,
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _middleNameCtrl,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Nome do Meio', prefixIcon: Icon(Icons.person_outline)),
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _lastNameCtrl,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Apelido *', prefixIcon: Icon(Icons.person)),
                validator: (v) => v == null || v.trim().isEmpty ? 'Campo obrigatório' : null,
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _cedulaCtrl,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Cédula / BI *', prefixIcon: Icon(Icons.badge)),
                validator: (v) => v == null || v.trim().isEmpty ? 'Campo obrigatório' : null,
              ),
              const SizedBox(height: 16),

              // Birth date
              InkWell(
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(8),
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'Data de Nascimento', prefixIcon: Icon(Icons.cake)),
                  child: Text(
                    _birthDate != null ? DateFormat('dd/MM/yyyy').format(_birthDate!) : 'Seleccionar data',
                    style: _birthDate == null
                        ? TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)
                        : null,
                  ),
                ),
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _placeOfBirthCtrl,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Local de Nascimento', prefixIcon: Icon(Icons.place)),
              ),
              const SizedBox(height: 12),

              // Sex
              DropdownButtonFormField<String>(
                value: _sex,
                decoration: const InputDecoration(labelText: 'Sexo', prefixIcon: Icon(Icons.wc)),
                items: const [
                  DropdownMenuItem(value: 'M', child: Text('Masculino')),
                  DropdownMenuItem(value: 'F', child: Text('Feminino')),
                ],
                onChanged: (v) => setState(() => _sex = v),
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _nationalityCtrl,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Nacionalidade', prefixIcon: Icon(Icons.flag)),
              ),
              const SizedBox(height: 24),

              _sectionHeader(context, 'Saúde'),
              const SizedBox(height: 12),

              TextFormField(
                controller: _heightCtrl,
                textInputAction: TextInputAction.next,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Altura (cm)', prefixIcon: Icon(Icons.height)),
              ),
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

              // Emergency contact
              InkWell(
                onTap: () => setState(() => _emergencyExpanded = !_emergencyExpanded),
                borderRadius: BorderRadius.circular(8),
                child: Row(
                  children: [
                    _sectionHeader(context, 'Contacto de Emergência'),
                    const Spacer(),
                    Icon(_emergencyExpanded ? Icons.expand_less : Icons.expand_more),
                  ],
                ),
              ),

              if (_emergencyExpanded) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _emergencyNameCtrl,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Nome', prefixIcon: Icon(Icons.person)),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _emergencyPhoneCtrl,
                  textInputAction: TextInputAction.next,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Telefone', prefixIcon: Icon(Icons.phone)),
                ),
              ],
              const SizedBox(height: 24),

              // Address
              InkWell(
                onTap: () => setState(() => _addressExpanded = !_addressExpanded),
                borderRadius: BorderRadius.circular(8),
                child: Row(
                  children: [
                    _sectionHeader(context, 'Morada'),
                    const Spacer(),
                    Icon(_addressExpanded ? Icons.expand_less : Icons.expand_more),
                  ],
                ),
              ),

              if (_addressExpanded) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _streetCtrl,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Rua', prefixIcon: Icon(Icons.home)),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _houseNumberCtrl,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(labelText: 'Nº Casa'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _buildingCtrl,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(labelText: 'Prédio'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _aptCtrl,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(labelText: 'Andar'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _bairroCtrl,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Bairro', prefixIcon: Icon(Icons.location_on)),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _municipioCtrl,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(labelText: 'Município'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _cityCtrl,
                        textInputAction: TextInputAction.done,
                        decoration: const InputDecoration(labelText: 'Cidade'),
                      ),
                    ),
                  ],
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
                    style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
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
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Text(isEditing ? 'Guardar Alterações' : 'Criar ${terms.student}'),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String text) {
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
