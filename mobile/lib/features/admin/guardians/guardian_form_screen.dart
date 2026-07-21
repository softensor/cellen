import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_client.dart';

class GuardianFormScreen extends ConsumerStatefulWidget {
  final String? guardianId;
  const GuardianFormScreen({super.key, this.guardianId});

  @override
  ConsumerState<GuardianFormScreen> createState() =>
      _GuardianFormScreenState();
}

class _GuardianFormScreenState extends ConsumerState<GuardianFormScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _isFetching = false;
  String? _error;

  // Fields
  final _firstNameCtrl = TextEditingController();
  final _middleNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _professionCtrl = TextEditingController();
  final _qualificationsCtrl = TextEditingController();
  final _idCardCtrl = TextEditingController();
  final _nifCtrl = TextEditingController();
  final _placeOfBirthCtrl = TextEditingController();
  final _nationalityCtrl = TextEditingController();
  final _mobileFirstCtrl = TextEditingController();
  final _mobileSecondCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _streetCtrl = TextEditingController();
  final _houseNumCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _municipioCtrl = TextEditingController();
  final _bairroCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  String? _sex;
  String? _civilState;
  DateTime? _birthDate;
  bool _obscurePassword = true;

  bool get _isEdit => widget.guardianId != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) _loadGuardian();
  }

  Future<void> _loadGuardian() async {
    setState(() => _isFetching = true);
    try {
      final api = ref.read(apiClientProvider);
      final data = await api.get('/guardians/${widget.guardianId}')
          as Map<String, dynamic>;
      _firstNameCtrl.text = data['first_name'] as String? ?? '';
      _middleNameCtrl.text = data['middle_name'] as String? ?? '';
      _lastNameCtrl.text = data['last_name'] as String? ?? '';
      _professionCtrl.text = data['profession'] as String? ?? '';
      _qualificationsCtrl.text = data['qualifications'] as String? ?? '';
      _idCardCtrl.text = data['id_card_number'] as String? ?? '';
      _nifCtrl.text = data['nif'] as String? ?? '';
      _placeOfBirthCtrl.text = data['place_of_birth'] as String? ?? '';
      _nationalityCtrl.text = data['nationality'] as String? ?? '';
      _birthDate = data['birth_date'] != null ? DateTime.tryParse(data['birth_date'] as String) : null;
      _mobileFirstCtrl.text = data['mobile_first'] as String? ?? '';
      _mobileSecondCtrl.text = data['mobile_second'] as String? ?? '';
      _emailCtrl.text = data['email'] as String? ?? '';
      _streetCtrl.text = data['street'] as String? ?? '';
      _houseNumCtrl.text = data['house_number'] as String? ?? '';
      _cityCtrl.text = data['city'] as String? ?? '';
      _municipioCtrl.text = data['municipio'] as String? ?? '';
      _bairroCtrl.text = data['bairro'] as String? ?? '';
      _sex = data['sex'] as String?;
      _civilState = data['civil_state'] as String?;
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _isFetching = false);
    }
  }

  @override
  void dispose() {
    for (final c in [
      _firstNameCtrl, _middleNameCtrl, _lastNameCtrl, _professionCtrl,
      _qualificationsCtrl, _idCardCtrl, _nifCtrl, _placeOfBirthCtrl,
      _nationalityCtrl, _mobileFirstCtrl, _mobileSecondCtrl,
      _emailCtrl, _streetCtrl, _houseNumCtrl, _cityCtrl, _municipioCtrl,
      _bairroCtrl, _usernameCtrl, _passwordCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      final body = <String, dynamic>{
        'first_name': _firstNameCtrl.text.trim(),
        'last_name': _lastNameCtrl.text.trim(),
        if (_middleNameCtrl.text.trim().isNotEmpty)
          'middle_name': _middleNameCtrl.text.trim(),
        if (_professionCtrl.text.trim().isNotEmpty)
          'profession': _professionCtrl.text.trim(),
        if (_qualificationsCtrl.text.trim().isNotEmpty)
          'qualifications': _qualificationsCtrl.text.trim(),
        if (_idCardCtrl.text.trim().isNotEmpty)
          'id_card_number': _idCardCtrl.text.trim(),
        if (_nifCtrl.text.trim().isNotEmpty)
          'nif': _nifCtrl.text.trim(),
        if (_placeOfBirthCtrl.text.trim().isNotEmpty)
          'place_of_birth': _placeOfBirthCtrl.text.trim(),
        if (_nationalityCtrl.text.trim().isNotEmpty)
          'nationality': _nationalityCtrl.text.trim(),
        if (_birthDate != null)
          'birth_date': '${_birthDate!.year.toString().padLeft(4, '0')}-${_birthDate!.month.toString().padLeft(2, '0')}-${_birthDate!.day.toString().padLeft(2, '0')}',
        if (_mobileFirstCtrl.text.trim().isNotEmpty)
          'mobile_first': _mobileFirstCtrl.text.trim(),
        if (_mobileSecondCtrl.text.trim().isNotEmpty)
          'mobile_second': _mobileSecondCtrl.text.trim(),
        if (_emailCtrl.text.trim().isNotEmpty)
          'email': _emailCtrl.text.trim(),
        if (_streetCtrl.text.trim().isNotEmpty)
          'street': _streetCtrl.text.trim(),
        if (_houseNumCtrl.text.trim().isNotEmpty)
          'house_number': _houseNumCtrl.text.trim(),
        if (_cityCtrl.text.trim().isNotEmpty)
          'city': _cityCtrl.text.trim(),
        if (_municipioCtrl.text.trim().isNotEmpty)
          'municipio': _municipioCtrl.text.trim(),
        if (_bairroCtrl.text.trim().isNotEmpty)
          'bairro': _bairroCtrl.text.trim(),
        if (_sex != null) 'sex': _sex,
        if (_civilState != null) 'civil_state': _civilState,
      };

      if (_isEdit) {
        await api.patch('/guardians/${widget.guardianId}', data: body);
      } else {
        body['username'] = _usernameCtrl.text.trim();
        body['password'] = _passwordCtrl.text;
        await api.post('/guardians', data: body);
      }

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isFetching) {
      return Scaffold(
        appBar: AppBar(
            title: Text(_isEdit ? 'Editar Encarregado' : 'Novo Encarregado')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Editar Encarregado' : 'Novo Encarregado'),
        actions: [
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            TextButton(
              onPressed: _submit,
              child: const Text('Guardar'),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_error != null)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Text(_error!,
                    style: TextStyle(color: Colors.red.shade800)),
              ),

            _SectionHeader(title: 'Dados Pessoais'),
            const SizedBox(height: 12),

            _field(_firstNameCtrl, 'Primeiro Nome *', required: true),
            const SizedBox(height: 12),
            _field(_middleNameCtrl, 'Nome do Meio'),
            const SizedBox(height: 12),
            _field(_lastNameCtrl, 'Apelido *', required: true),
            const SizedBox(height: 12),

            InkWell(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _birthDate ?? DateTime(1985),
                  firstDate: DateTime(1930),
                  lastDate: DateTime.now(),
                );
                if (picked != null) setState(() => _birthDate = picked);
              },
              borderRadius: BorderRadius.circular(8),
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Data de Nascimento',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.cake),
                ),
                child: Text(
                  _birthDate != null
                      ? DateFormat('dd/MM/yyyy').format(_birthDate!)
                      : 'Seleccionar data',
                  style: _birthDate == null
                      ? TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)
                      : null,
                ),
              ),
            ),
            const SizedBox(height: 12),
            _field(_placeOfBirthCtrl, 'Local de Nascimento'),
            const SizedBox(height: 12),
            _field(_nationalityCtrl, 'Nacionalidade'),
            const SizedBox(height: 12),

            DropdownButtonFormField<String>(
              value: _sex,
              decoration: const InputDecoration(
                labelText: 'Sexo',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'M', child: Text('Masculino')),
                DropdownMenuItem(value: 'F', child: Text('Feminino')),
              ],
              onChanged: (v) => setState(() => _sex = v),
            ),
            const SizedBox(height: 12),

            DropdownButtonFormField<String>(
              value: _civilState,
              decoration: const InputDecoration(
                labelText: 'Estado Civil',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(
                    value: 'single', child: Text('Solteiro(a)')),
                DropdownMenuItem(
                    value: 'married', child: Text('Casado(a)')),
                DropdownMenuItem(
                    value: 'divorced', child: Text('Divorciado(a)')),
                DropdownMenuItem(
                    value: 'widowed', child: Text('Viúvo(a)')),
              ],
              onChanged: (v) => setState(() => _civilState = v),
            ),
            const SizedBox(height: 12),
            _field(_idCardCtrl, 'Nº Bilhete de Identidade'),
            const SizedBox(height: 12),
            _field(_nifCtrl, 'NIF (Nº de Identificação Fiscal)'),
            const SizedBox(height: 12),
            _field(_professionCtrl, 'Profissão'),
            const SizedBox(height: 12),
            _field(_qualificationsCtrl, 'Habilitações'),

            const SizedBox(height: 24),
            _SectionHeader(title: 'Contactos'),
            const SizedBox(height: 12),

            _field(_mobileFirstCtrl, 'Telemóvel Principal'),
            const SizedBox(height: 12),
            _field(_mobileSecondCtrl, 'Telemóvel Secundário'),
            const SizedBox(height: 12),
            _field(_emailCtrl, 'Email',
                keyboardType: TextInputType.emailAddress),

            const SizedBox(height: 24),
            _SectionHeader(title: 'Morada'),
            const SizedBox(height: 12),

            _field(_streetCtrl, 'Rua / Avenida'),
            const SizedBox(height: 12),
            _field(_houseNumCtrl, 'Nº da Casa'),
            const SizedBox(height: 12),
            _field(_bairroCtrl, 'Bairro'),
            const SizedBox(height: 12),
            _field(_municipioCtrl, 'Município'),
            const SizedBox(height: 12),
            _field(_cityCtrl, 'Cidade / Província'),

            if (!_isEdit) ...[
              const SizedBox(height: 24),
              _SectionHeader(title: 'Conta de Acesso'),
              const SizedBox(height: 4),
              Text(
                'Credenciais para o encarregado entrar na plataforma',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _usernameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nome de Utilizador *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.account_circle),
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Campo obrigatório' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _passwordCtrl,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: 'Palavra-passe *',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.lock),
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePassword
                        ? Icons.visibility
                        : Icons.visibility_off),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
                validator: (v) =>
                    v == null || v.length < 6 ? 'Mínimo 6 caracteres' : null,
              ),
            ],

            if (_isEdit) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                icon: const Icon(Icons.lock_reset),
                label: const Text('Repor Palavra-passe'),
                onPressed: () => _showResetPasswordDialog(context),
              ),
            ],

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Future<void> _showResetPasswordDialog(BuildContext context) async {
    final pwCtrl = TextEditingController();
    bool obscure = true;
    String? dialogError;

    await showDialog(useRootNavigator: false, 
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Repor Palavra-passe'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: pwCtrl,
                obscureText: obscure,
                decoration: InputDecoration(
                  labelText: 'Nova Palavra-passe',
                  suffixIcon: IconButton(
                    icon: Icon(obscure ? Icons.visibility : Icons.visibility_off),
                    onPressed: () => setDialogState(() => obscure = !obscure),
                  ),
                ),
              ),
              if (dialogError != null) ...[
                const SizedBox(height: 8),
                Text(dialogError!,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 12)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () async {
                if (pwCtrl.text.length < 6) {
                  setDialogState(() => dialogError = 'Mínimo 6 caracteres');
                  return;
                }
                try {
                  final api = ref.read(apiClientProvider);
                  await api.patch(
                    '/guardians/${widget.guardianId}/set-password',
                    data: {'password': pwCtrl.text},
                  );
                  if (ctx.mounted) Navigator.of(ctx).pop();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Palavra-passe reposta com sucesso')),
                    );
                  }
                } catch (e) {
                  setDialogState(() => dialogError = e.toString());
                }
              },
              child: const Text('Confirmar'),
            ),
          ],
        ),
      ),
    );
    pwCtrl.dispose();
  }

  Widget _field(
    TextEditingController ctrl,
    String label, {
    bool required = false,
    TextInputType? keyboardType,
  }) {
    return TextFormField(
      controller: ctrl,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      validator: required
          ? (v) => (v == null || v.trim().isEmpty) ? 'Campo obrigatório' : null
          : null,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
    );
  }
}
