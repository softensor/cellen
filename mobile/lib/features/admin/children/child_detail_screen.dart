import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_client.dart';
import '../../../core/models/caderneta.dart';
import '../../../core/models/child.dart';
import '../../../core/models/guardian.dart';
import '../../../core/models/invoice.dart';
import '../../../core/models/school_terms.dart';
import '../../../core/providers/currency_provider.dart';
import '../../../core/widgets/app_error_widget.dart';
import '../finance/fee_automation_common.dart';
import 'children_list_screen.dart' show childrenProvider;

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------
final childProvider =
    FutureProvider.autoDispose.family<Child, String>((ref, id) async {
  final api = ref.read(apiClientProvider);
  final data = await api.get('/children/$id');
  return Child.fromJson(data as Map<String, dynamic>);
});

final childGuardiansProvider =
    FutureProvider.autoDispose.family<List<Guardian>, String>((ref, id) async {
  final api = ref.read(apiClientProvider);
  final data = await api.get('/children/$id/guardians') as List;
  return data.map((e) => Guardian.fromJson(e as Map<String, dynamic>)).toList();
});

final childCadernetasProvider =
    FutureProvider.autoDispose.family<List<Caderneta>, String>((ref, id) async {
  final api = ref.read(apiClientProvider);
  final data = await api.get('/children/$id/cadernetas') as List;
  return data
      .map((e) => Caderneta.fromJson(e as Map<String, dynamic>))
      .toList();
});

final childInvoicesProvider =
    FutureProvider.autoDispose.family<List<Invoice>, String>((ref, id) async {
  final api = ref.read(apiClientProvider);
  final data = await api
      .get('/finance/invoices', queryParameters: {'child_id': id}) as List;
  return data.map((e) => Invoice.fromJson(e as Map<String, dynamic>)).toList();
});

final childFinanceSummaryProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, id) async {
  final api = ref.read(apiClientProvider);
  final data = await api.get('/billing/students/$id/summary') as Map;
  return Map<String, dynamic>.from(data);
});

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------
Future<void> _uploadPhoto(
    BuildContext context, WidgetRef ref, String childId) async {
  final picker = ImagePicker();
  final image =
      await picker.pickImage(source: ImageSource.gallery, maxWidth: 800);
  if (image == null) return;
  try {
    final api = ref.read(apiClientProvider);
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(image.path, filename: image.name),
    });
    await api.post('/children/$childId/photo', data: formData);
    ref.invalidate(childProvider(childId));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Foto actualizada')),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao enviar foto: $e')),
      );
    }
  }
}

class ChildDetailScreen extends ConsumerWidget {
  final String id;

  const ChildDetailScreen({super.key, required this.id});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final childAsync = ref.watch(childProvider(id));

    final terms = SchoolTerms.of(ref.watch(schoolInfoProvider).valueOrNull);
    return childAsync.when(
      loading: () => Scaffold(
        appBar: AppBar(title: Text(terms.student)),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: Text(terms.student)),
        body: AppErrorWidget(
            error: e, onRetry: () => ref.invalidate(childProvider(id))),
      ),
      data: (child) => _ChildDetailView(child: child),
    );
  }
}

class _ChildDetailView extends ConsumerWidget {
  final Child child;

  const _ChildDetailView({required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final terms = SchoolTerms.of(ref.watch(schoolInfoProvider).valueOrNull);
    final showCaderneta = !terms.isK12;

    return DefaultTabController(
      length: showCaderneta ? 5 : 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(child.fullName),
          actions: [
            IconButton(
              icon: const Icon(Icons.edit),
              tooltip: 'Editar',
              onPressed: () => context.push('/admin/children/${child.id}/edit'),
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabs: [
              const Tab(text: 'Informação'),
              const Tab(text: 'Encarregados'),
              if (showCaderneta) const Tab(text: 'Caderneta'),
              const Tab(text: 'Facturas'),
              const Tab(text: 'Financeiro'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _InfoTab(
                child: child,
                onUploadPhoto: () => _uploadPhoto(context, ref, child.id)),
            _GuardiansTab(childId: child.id),
            if (showCaderneta) _CadernetaTab(childId: child.id),
            _InvoicesTab(childId: child.id),
            _FinanceTab(childId: child.id),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Info Tab
// ---------------------------------------------------------------------------
class _InfoTab extends StatelessWidget {
  final Child child;
  final VoidCallback? onUploadPhoto;
  const _InfoTab({required this.child, this.onUploadPhoto});

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd/MM/yyyy');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Photo + name header
          Center(
            child: Column(
              children: [
                GestureDetector(
                  onTap: onUploadPhoto,
                  child: Stack(
                    children: [
                      _ChildPhotoAvatar(
                          photoUrl: child.photoUrl,
                          name: child.fullName,
                          radius: 48),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.camera_alt,
                              size: 16,
                              color: Theme.of(context).colorScheme.onPrimary),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  child.fullName,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                if (child.turmaName != null)
                  Chip(
                    label: Text(child.turmaName!),
                    avatar: const Icon(Icons.school, size: 16),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          _SectionTitle('Dados Pessoais'),
          _InfoRow('Cédula', child.cedula),
          if (child.birthDate != null)
            _InfoRow('Data de Nascimento', df.format(child.birthDate!)),
          if (child.placeOfBirth != null && child.placeOfBirth!.isNotEmpty)
            _InfoRow('Local de Nascimento', child.placeOfBirth!),
          _InfoRow('Sexo', child.sexLabel),
          if (child.nationality != null && child.nationality!.isNotEmpty)
            _InfoRow('Nacionalidade', child.nationality!),
          if (child.height != null) _InfoRow('Altura', '${child.height} cm'),
          if (!child.isActive) _InfoRow('Estado', 'Inactivo'),

          if (child.specialNeeds != null && child.specialNeeds!.isNotEmpty) ...[
            const SizedBox(height: 16),
            _SectionTitle('Necessidades Especiais'),
            Text(child.specialNeeds!),
          ],

          if (child.medicalPrescription != null &&
              child.medicalPrescription!.isNotEmpty) ...[
            const SizedBox(height: 16),
            _SectionTitle('Prescrição Médica'),
            Text(child.medicalPrescription!),
          ],

          if (child.emergencyContactName != null &&
              child.emergencyContactName!.isNotEmpty) ...[
            const SizedBox(height: 16),
            _SectionTitle('Contacto de Emergência'),
            _InfoRow('Nome', child.emergencyContactName!),
            if (child.emergencyContactPhone != null)
              _InfoRow('Telefone', child.emergencyContactPhone!),
          ],

          if (child.fullAddress != null) ...[
            const SizedBox(height: 16),
            _SectionTitle('Morada'),
            _InfoRow('Endereço', child.fullAddress!),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Guardians Tab
// ---------------------------------------------------------------------------
class _GuardiansTab extends ConsumerStatefulWidget {
  final String childId;
  const _GuardiansTab({required this.childId});

  @override
  ConsumerState<_GuardiansTab> createState() => _GuardiansTabState();
}

class _GuardiansTabState extends ConsumerState<_GuardiansTab> {
  static const _relationships = [
    ('father', 'Pai'),
    ('mother', 'Mãe'),
    ('grandparent', 'Avô/Avó'),
    ('legal_guardian', 'Tutor Legal'),
    ('sibling', 'Irmão/Irmã'),
    ('uncle_aunt', 'Tio/Tia'),
    ('other', 'Outro'),
  ];

  Future<void> _showLinkDialog() async {
    // Load all school guardians
    final api = ref.read(apiClientProvider);
    List allGuardians = [];
    try {
      allGuardians = await api.get('/guardians') as List;
    } catch (_) {
      return;
    }

    if (!mounted) return;

    String? selectedGuardianId;
    String selectedRelationship = 'father';
    bool isPrimary = false;

    await showDialog(
      useRootNavigator: false,
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Ligar Encarregado'),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                      labelText: 'Encarregado *', border: OutlineInputBorder()),
                  items: allGuardians
                      .map((g) => DropdownMenuItem<String>(
                            value: g['id'].toString(),
                            child: Text('${g['first_name']} ${g['last_name']}'),
                          ))
                      .toList(),
                  onChanged: (v) => setS(() => selectedGuardianId = v),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: selectedRelationship,
                  decoration: const InputDecoration(
                      labelText: 'Parentesco', border: OutlineInputBorder()),
                  items: _relationships
                      .map((r) =>
                          DropdownMenuItem(value: r.$1, child: Text(r.$2)))
                      .toList(),
                  onChanged: (v) => setS(() => selectedRelationship = v!),
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  value: isPrimary,
                  onChanged: (v) => setS(() => isPrimary = v!),
                  title: const Text('Contacto principal'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: selectedGuardianId == null
                  ? null
                  : () async {
                      try {
                        await api.post(
                          '/guardians/$selectedGuardianId/children',
                          data: {
                            'child_id': widget.childId,
                            'relationship_type': selectedRelationship,
                            'is_primary_contact': isPrimary,
                          },
                        );
                        ref.invalidate(childGuardiansProvider(widget.childId));
                        if (mounted) Navigator.pop(ctx);
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(e.toString())));
                        }
                      }
                    },
              child: const Text('Ligar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _unlink(String guardianId, String guardianName) async {
    final confirmed = await showDialog<bool>(
      useRootNavigator: false,
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remover ligação'),
        content: Text(
            'Remover $guardianName d${SchoolTerms.of(ref.read(schoolInfoProvider).valueOrNull).isK12 ? 'este aluno' : 'esta criança'}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final api = ref.read(apiClientProvider);
      try {
        await api.delete('/guardians/$guardianId/children/${widget.childId}');
        ref.invalidate(childGuardiansProvider(widget.childId));
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(e.toString())));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final guardiansAsync = ref.watch(childGuardiansProvider(widget.childId));
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showLinkDialog,
        icon: const Icon(Icons.person_add),
        label: const Text('Ligar Encarregado'),
      ),
      body: guardiansAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AppErrorWidget(
            error: e,
            onRetry: () =>
                ref.invalidate(childGuardiansProvider(widget.childId))),
        data: (guardians) {
          if (guardians.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.people_outline,
                      size: 64,
                      color: Theme.of(context).colorScheme.outlineVariant),
                  const SizedBox(height: 16),
                  const Text('Nenhum encarregado ligado'),
                  const SizedBox(height: 8),
                  const Text('Use o botão abaixo para ligar um encarregado',
                      style: TextStyle(color: Colors.grey, fontSize: 13)),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
            itemCount: guardians.length,
            itemBuilder: (context, i) {
              final g = guardians[i];
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: CircleAvatar(child: Text(g.fullName[0])),
                  title: Text(g.fullName),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(g.relationshipLabel),
                      if (g.phone != null)
                        Text(g.phone!, style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (g.isPrimary)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color:
                                Theme.of(context).colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text('Principal',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onPrimaryContainer)),
                        ),
                      IconButton(
                        icon: const Icon(Icons.link_off,
                            color: Colors.red, size: 20),
                        tooltip: 'Remover ligação',
                        onPressed: () => _unlink(g.id, g.fullName),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Caderneta Tab
// ---------------------------------------------------------------------------
class _CadernetaTab extends ConsumerWidget {
  final String childId;
  const _CadernetaTab({required this.childId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(childCadernetasProvider(childId));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => AppErrorWidget(error: e),
      data: (cadernetas) {
        if (cadernetas.isEmpty) {
          return const Center(child: Text('Nenhuma caderneta registada'));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: cadernetas.length,
          itemBuilder: (context, i) {
            final c = cadernetas[i];
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: const Icon(Icons.book),
                title: Text(DateFormat('dd/MM/yyyy').format(c.reportDate)),
                subtitle: Text(
                  [
                    if (c.breakfastRating != null)
                      'Pequeno-almoço: ${c.breakfastRating}',
                    if (c.lunchRating != null) 'Almoço: ${c.lunchRating}',
                  ].join(' · '),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Invoices Tab
// ---------------------------------------------------------------------------
class _InvoicesTab extends ConsumerWidget {
  final String childId;
  const _InvoicesTab({required this.childId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(childInvoicesProvider(childId));
    final currency = ref.watch(currencyFormatProvider);

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => AppErrorWidget(error: e),
      data: (invoices) {
        if (invoices.isEmpty) {
          return const Center(child: Text('Nenhuma factura encontrada'));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: invoices.length,
          itemBuilder: (context, i) {
            final inv = invoices[i];
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(
                    DateFormat('MMMM yyyy', 'pt_PT').format(inv.referenceMonth),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(currency.format(inv.totalAmount)),
                trailing:
                    _StatusChip(status: inv.status, label: inv.statusLabel),
              ),
            );
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Finance Tab
// ---------------------------------------------------------------------------
class _FinanceTab extends ConsumerWidget {
  final String childId;
  const _FinanceTab({required this.childId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(childFinanceSummaryProvider(childId));
    final currency = ref.watch(currencyFormatProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => AppErrorWidget(
        error: error,
        onRetry: () => ref.invalidate(childFinanceSummaryProvider(childId)),
      ),
      data: (summary) {
        final profile =
            Map<String, dynamic>.from(summary['profile'] as Map? ?? {});
        final preview = summary['preview'] == null
            ? null
            : Map<String, dynamic>.from(summary['preview'] as Map);
        final previewError = summary['preview_error'] == null
            ? null
            : Map<String, dynamic>.from(summary['preview_error'] as Map);
        final modalities =
            (summary['modalities'] as List? ?? const []).cast<Map>();
        final transport =
            (summary['transport'] as List? ?? const []).cast<Map>();
        final previewStudents =
            (preview?['students'] as List? ?? const []).cast<Map>();
        final student = previewStudents.isEmpty
            ? null
            : Map<String, dynamic>.from(previewStudents.first);
        final total = (student?['total'] as num?)?.toDouble();
        final planStatus = profile['status']?.toString() ?? 'active';
        return RefreshIndicator(
          onRefresh: () async =>
              ref.invalidate(childFinanceSummaryProvider(childId)),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(
                          child: Text(
                            'Ficha financeira',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        _StatusChip(
                            status: planStatus, label: _planLabel(planStatus)),
                      ]),
                      const SizedBox(height: 10),
                      _InfoRow(
                        'Propina mensal',
                        currency.format(
                          (profile['effective_tuition_price'] as num?)
                                  ?.toDouble() ??
                              0,
                        ),
                      ),
                      _InfoRow(
                        'Encarregado de facturação',
                        profile['billing_guardian_name']?.toString() ??
                            'Não definido',
                      ),
                      _InfoRow(
                        'Dia de cobrança',
                        '${profile['billing_day'] ?? 1}',
                      ),
                      if (profile['tuition_override'] != null)
                        _InfoRow(
                          'Valor próprio',
                          '${currency.format((profile['tuition_override'] as num).toDouble())} '
                              '(substitui o valor padrão)',
                        ),
                      const SizedBox(height: 8),
                      Row(children: [
                        OutlinedButton.icon(
                          onPressed: () => _editProfile(context, ref, summary),
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          label: const Text('Editar ficha'),
                        ),
                        const SizedBox(width: 8),
                        TextButton.icon(
                          onPressed: () =>
                              context.push('/admin/finance/billing-run'),
                          icon: const Icon(Icons.bolt_outlined, size: 18),
                          label: const Text('Gerar dívidas'),
                        ),
                      ]),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const Icon(Icons.receipt_long_outlined, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Cobrança deste mês',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        if (total != null)
                          Text(
                            currency.format(total),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                      ]),
                      const SizedBox(height: 8),
                      if (previewError != null)
                        Text(
                          previewError['message']?.toString() ??
                              'Não foi possível calcular a cobrança.',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        )
                      else if (student == null)
                        const Text('Sem valores a cobrar neste mês.')
                      else ...[
                        for (final raw
                            in (student['lines'] as List? ?? const [])
                                .cast<Map>())
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      raw['service_label']?.toString() ??
                                          raw['description']?.toString() ??
                                          'Serviço',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    if ((raw['discount_amount'] as num? ?? 0) >
                                        0)
                                      Text(
                                        'Desconto ${raw['discount_pct']}%',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                  ],
                                ),
                              ),
                              Text(currency.format(
                                (raw['line_total'] as num?)?.toDouble() ?? 0,
                              )),
                            ]),
                          ),
                        if (student['sibling_discount_applied'] == true)
                          const Padding(
                            padding: EdgeInsets.only(top: 6),
                            child: Text(
                              'Desconto de irmãos aplicado.',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _SectionTitle('Modalidades'),
              if (modalities.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text('Sem modalidades inscritas.'),
                )
              else
                for (final raw in modalities)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: Text(
                          raw['modality_name']?.toString() ?? 'Modalidade'),
                      subtitle: Text(
                        'Início ${formatIsoDate(raw['start_date']?.toString())}'
                        '${raw['end_date'] == null ? '' : ' · fim ${formatIsoDate(raw['end_date']?.toString())}'}',
                      ),
                      trailing: raw['status'] == 'active'
                          ? TextButton(
                              onPressed: () => _endModality(
                                  context, ref, raw['id'].toString()),
                              child: const Text('Encerrar'),
                            )
                          : _StatusChip(
                              status: raw['status']?.toString() ?? 'ended',
                              label: raw['status'] == 'withdrawn'
                                  ? 'Desistiu'
                                  : 'Terminada',
                            ),
                    ),
                  ),
              TextButton.icon(
                onPressed: () => context.push('/admin/finance/modalities'),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Gerir modalidades'),
              ),
              const SizedBox(height: 8),
              _SectionTitle('Transporte escolar'),
              if (transport.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text('Sem transporte atribuído.'),
                )
              else
                for (final raw in transport)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: Text(raw['route_name']?.toString() ?? 'Rota'),
                      subtitle: Text(
                        'Início ${formatIsoDate(raw['start_date']?.toString())}'
                        '${raw['end_date'] == null ? '' : ' · fim ${formatIsoDate(raw['end_date']?.toString())}'}',
                      ),
                      trailing: raw['status'] == 'active'
                          ? TextButton(
                              onPressed: () => _endTransport(
                                  context, ref, raw['id'].toString()),
                              child: const Text('Encerrar'),
                            )
                          : _StatusChip(
                              status: raw['status']?.toString() ?? 'ended',
                              label: 'Terminado',
                            ),
                    ),
                  ),
              TextButton.icon(
                onPressed: () => context.push('/admin/finance/transport'),
                icon: const Icon(Icons.directions_bus_outlined, size: 18),
                label: const Text('Gerir transporte'),
              ),
              const SizedBox(height: 8),
              _SectionTitle('Plano no Finreg'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(children: [
                    _InfoRow(
                      'Identificador',
                      profile['plan_external_id']?.toString() ?? '—',
                    ),
                    _InfoRow(
                      'Revisão do plano',
                      profile['plan_revision']?.toString() ?? '—',
                    ),
                    _InfoRow(
                      'Próxima execução',
                      formatIsoDate(
                        profile['plan_next_run_date']?.toString(),
                      ),
                    ),
                    _InfoRow(
                      'Estado',
                      profile['plan_stale'] == true
                          ? 'Desactualizado — reconstrua os planos'
                          : 'Em dia',
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }

  Future<void> _editProfile(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> summary,
  ) async {
    final changed = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (_) => _FinanceProfileDialog(
        childId: childId,
        summary: summary,
      ),
    );
    if (changed == true) {
      ref.invalidate(childFinanceSummaryProvider(childId));
    }
  }

  Future<void> _endModality(
    BuildContext context,
    WidgetRef ref,
    String enrollmentId,
  ) async {
    try {
      await ref.read(apiClientProvider).post(
        '/billing/modality-enrollments/$enrollmentId/end',
        data: {'status': 'ended'},
      );
      ref.invalidate(childFinanceSummaryProvider(childId));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Modalidade encerrada.')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro: $error')));
      }
    }
  }

  Future<void> _endTransport(
    BuildContext context,
    WidgetRef ref,
    String assignmentId,
  ) async {
    try {
      await ref.read(apiClientProvider).post(
        '/billing/transport/assignments/$assignmentId/end',
        data: {'status': 'ended'},
      );
      ref.invalidate(childFinanceSummaryProvider(childId));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Transporte encerrado.')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro: $error')));
      }
    }
  }
}

String _planLabel(String status) => switch (status) {
      'active' => 'Activo',
      'paused' => 'Pausado',
      'withdrawn' => 'Encerrado',
      _ => status,
    };

class _FinanceProfileDialog extends ConsumerStatefulWidget {
  const _FinanceProfileDialog({required this.childId, required this.summary});

  final String childId;
  final Map<String, dynamic> summary;

  @override
  ConsumerState<_FinanceProfileDialog> createState() =>
      _FinanceProfileDialogState();
}

class _FinanceProfileDialogState extends ConsumerState<_FinanceProfileDialog> {
  late final TextEditingController _tuitionOverride;
  late final TextEditingController _billingDay;
  String? _guardianId;
  String _status = 'active';
  bool _saving = false;
  String? _error;

  Map<String, dynamic> get _profile =>
      Map<String, dynamic>.from(widget.summary['profile'] as Map? ?? {});

  @override
  void initState() {
    super.initState();
    final profile = _profile;
    _tuitionOverride = TextEditingController(
      text: profile['tuition_override'] == null
          ? ''
          : (profile['tuition_override'] as num).toString(),
    );
    _billingDay = TextEditingController(
      text: (profile['billing_day'] ?? 1).toString(),
    );
    _guardianId = profile['billing_guardian_id']?.toString();
    _status = profile['status']?.toString() ?? 'active';
  }

  @override
  void dispose() {
    _tuitionOverride.dispose();
    _billingDay.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final guardians = ref.watch(childGuardiansProvider(widget.childId));
    return AlertDialog(
      title: const Text('Ficha financeira'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: _tuitionOverride,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Propina mensal própria (Kz)',
                helperText: 'Deixe vazio para usar o valor padrão da escola.',
              ),
            ),
            const SizedBox(height: 10),
            guardians.when(
              loading: () => const LinearProgressIndicator(),
              error: (_, __) =>
                  const Text('Não foi possível carregar os encarregados.'),
              data: (rows) => DropdownButtonFormField<String?>(
                value: _guardianId,
                decoration: const InputDecoration(
                  labelText: 'Encarregado de facturação',
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Automático (primeiro encarregado)'),
                  ),
                  for (final guardian in rows)
                    DropdownMenuItem<String?>(
                      value: guardian.id,
                      child: Text(
                        '${guardian.firstName} ${guardian.lastName}',
                      ),
                    ),
                ],
                onChanged: (value) => setState(() => _guardianId = value),
              ),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _billingDay,
                  keyboardType: TextInputType.number,
                  decoration:
                      const InputDecoration(labelText: 'Dia de cobrança'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _status,
                  decoration:
                      const InputDecoration(labelText: 'Estado do plano'),
                  items: const [
                    DropdownMenuItem(value: 'active', child: Text('Activo')),
                    DropdownMenuItem(value: 'paused', child: Text('Pausado')),
                    DropdownMenuItem(
                      value: 'withdrawn',
                      child: Text('Encerrado'),
                    ),
                  ],
                  onChanged: (value) =>
                      setState(() => _status = value ?? 'active'),
                ),
              ),
            ]),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ]),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'A guardar…' : 'Guardar'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(apiClientProvider).put(
        '/billing/students/${widget.childId}/profile',
        data: {
          'billing_guardian_id': _guardianId,
          'tuition_override': _tuitionOverride.text.trim().isEmpty
              ? null
              : parseMoney(_tuitionOverride.text),
          'billing_day': int.tryParse(_billingDay.text.trim()),
          'status': _status,
        },
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      setState(() {
        _saving = false;
        _error = error.toString();
      });
    }
  }
}

// ---------------------------------------------------------------------------
// Shared widgets
// ---------------------------------------------------------------------------

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
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

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 160,
            child: Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  final String label;
  const _StatusChip({required this.status, required this.label});

  @override
  Widget build(BuildContext context) {
    Color color;
    switch (status) {
      case 'paid':
        color = Colors.green;
        break;
      case 'overdue':
        color = Colors.red;
        break;
      case 'partially_paid':
        color = Colors.orange;
        break;
      case 'cancelled':
        color = Colors.grey;
        break;
      default:
        color = Colors.blue;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        label,
        style:
            TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _ChildPhotoAvatar extends StatelessWidget {
  final String? photoUrl;
  final String name;
  final double radius;
  const _ChildPhotoAvatar(
      {this.photoUrl, required this.name, this.radius = 24});

  @override
  Widget build(BuildContext context) {
    if (photoUrl != null && photoUrl!.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundImage: NetworkImage(
            '$kMediaBase${photoUrl!.startsWith('/') ? photoUrl! : '/$photoUrl'}'),
        onBackgroundImageError: (_, __) {},
      );
    }
    final initials = name.isNotEmpty
        ? name.trim().split(' ').take(2).map((w) => w[0]).join()
        : '?';
    return CircleAvatar(
      radius: radius,
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      child: Text(
        initials.toUpperCase(),
        style: TextStyle(
          color: Theme.of(context).colorScheme.onPrimaryContainer,
          fontWeight: FontWeight.bold,
          fontSize: radius * 0.6,
        ),
      ),
    );
  }
}
