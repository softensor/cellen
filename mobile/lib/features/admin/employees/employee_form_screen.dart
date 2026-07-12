import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_client.dart';
import '../../../core/models/employee.dart';
import 'employees_list_screen.dart' show employeesProvider;

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------
class EmployeeFormScreen extends ConsumerStatefulWidget {
  final String? employeeId;
  const EmployeeFormScreen({super.key, this.employeeId});

  @override
  ConsumerState<EmployeeFormScreen> createState() =>
      _EmployeeFormScreenState();
}

class _EmployeeFormScreenState extends ConsumerState<EmployeeFormScreen> {
  final _formKey = GlobalKey<FormState>();

  final _firstNameCtrl = TextEditingController();
  final _middleNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _cedulaCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _positionCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  String _employeeType = 'teacher';
  DateTime? _hireDate;
  bool _isLoading = false;
  bool _isLoadingEmployee = false;
  bool _obscurePassword = true;
  String? _error;

  bool get isEditing => widget.employeeId != null;

  @override
  void initState() {
    super.initState();
    if (isEditing) _loadEmployee();
  }

  Future<void> _loadEmployee() async {
    setState(() => _isLoadingEmployee = true);
    try {
      final api = ref.read(apiClientProvider);
      final data = await api.get('/employees/${widget.employeeId}');
      final emp = Employee.fromJson(data as Map<String, dynamic>);
      _firstNameCtrl.text = emp.firstName;
      _middleNameCtrl.text = emp.middleName ?? '';
      _lastNameCtrl.text = emp.lastName;
      _cedulaCtrl.text = emp.cedula ?? '';
      _phoneCtrl.text = emp.phone ?? '';
      _emailCtrl.text = emp.email ?? '';
      _positionCtrl.text = emp.position ?? '';
      setState(() {
        _employeeType = emp.employeeType;
        _hireDate = emp.hireDate;
        _isLoadingEmployee = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoadingEmployee = false;
      });
    }
  }

  Future<void> _pickHireDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _hireDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _hireDate = picked);
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
      'employee_type': _employeeType,
    };
    if (_middleNameCtrl.text.trim().isNotEmpty) {
      body['middle_name'] = _middleNameCtrl.text.trim();
    }
    if (_cedulaCtrl.text.trim().isNotEmpty) {
      body['cedula'] = _cedulaCtrl.text.trim();
    }
    if (_phoneCtrl.text.trim().isNotEmpty) {
      body['phone'] = _phoneCtrl.text.trim();
    }
    if (_emailCtrl.text.trim().isNotEmpty) {
      body['email'] = _emailCtrl.text.trim();
    }
    if (_positionCtrl.text.trim().isNotEmpty) {
      body['position'] = _positionCtrl.text.trim();
    }
    if (_hireDate != null) {
      body['hire_date'] =
          '${_hireDate!.year.toString().padLeft(4, '0')}-${_hireDate!.month.toString().padLeft(2, '0')}-${_hireDate!.day.toString().padLeft(2, '0')}';
    }
    if (!isEditing) {
      body['username'] = _usernameCtrl.text.trim();
      body['password'] = _passwordCtrl.text;
    }

    try {
      final api = ref.read(apiClientProvider);
      if (isEditing) {
        await api.patch('/employees/${widget.employeeId}', data: body);
      } else {
        await api.post('/employees', data: body);
      }
      ref.invalidate(employeesProvider);
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
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _positionCtrl.dispose();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingEmployee) {
      return Scaffold(
        appBar: AppBar(
            title:
                Text(isEditing ? 'Editar Funcionário' : 'Novo Funcionário')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Editar Funcionário' : 'Novo Funcionário'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sectionHeader(context, 'Dados Pessoais'),
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
                  labelText: 'Cédula / BI',
                  prefixIcon: Icon(Icons.badge),
                ),
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _phoneCtrl,
                textInputAction: TextInputAction.next,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Telefone',
                  prefixIcon: Icon(Icons.phone),
                ),
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _emailCtrl,
                textInputAction: TextInputAction.next,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.email),
                ),
              ),
              const SizedBox(height: 24),

              _sectionHeader(context, 'Dados de Emprego'),
              const SizedBox(height: 12),

              DropdownButtonFormField<String>(
                value: _employeeType,
                decoration: const InputDecoration(
                  labelText: 'Tipo de Funcionário *',
                  prefixIcon: Icon(Icons.work),
                ),
                items: const [
                  DropdownMenuItem(
                      value: 'teacher', child: Text('Educador(a)')),
                  DropdownMenuItem(
                      value: 'staff', child: Text('Auxiliar')),
                  DropdownMenuItem(
                      value: 'admin', child: Text('Administração')),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _employeeType = v);
                },
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _positionCtrl,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Cargo / Função',
                  prefixIcon: Icon(Icons.business_center),
                ),
              ),
              const SizedBox(height: 12),

              InkWell(
                onTap: _pickHireDate,
                borderRadius: BorderRadius.circular(8),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Data de Admissão',
                    prefixIcon: Icon(Icons.calendar_today),
                  ),
                  child: Text(
                    _hireDate != null
                        ? DateFormat('dd/MM/yyyy').format(_hireDate!)
                        : 'Seleccionar data',
                    style: _hireDate == null
                        ? TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant)
                        : null,
                  ),
                ),
              ),

              // User account — required when creating
              if (!isEditing) ...[
                const SizedBox(height: 24),
                _sectionHeader(context, 'Conta de Acesso'),
                const SizedBox(height: 4),
                Text(
                  'Credenciais para entrar na plataforma',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _usernameCtrl,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Nome de Utilizador *',
                    prefixIcon: Icon(Icons.account_circle),
                  ),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Campo obrigatório' : null,
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _passwordCtrl,
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    labelText: 'Palavra-passe *',
                    prefixIcon: const Icon(Icons.lock),
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePassword
                          ? Icons.visibility
                          : Icons.visibility_off),
                      onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  validator: (v) => v == null || v.length < 6
                      ? 'Mínimo 6 caracteres'
                      : null,
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
                    : Text(isEditing
                        ? 'Guardar Alterações'
                        : 'Criar Funcionário'),
              ),

              if (isEditing) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.lock_reset),
                  label: const Text('Repor Palavra-passe'),
                  onPressed: () => _showResetPasswordDialog(context),
                ),
              ],

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showResetPasswordDialog(BuildContext context) async {
    final pwCtrl = TextEditingController();
    bool obscure = true;
    String? dialogError;

    await showDialog(
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
                    '/employees/${widget.employeeId}/set-password',
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

  Widget _sectionHeader(BuildContext context, String text) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.bold,
          ),
    );
  }
}
