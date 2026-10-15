import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../auth/auth_controller.dart';
import 'confirmation/confirmation_page.dart';
import 'workorder_repository.dart';

class WorkorderDetailPage extends ConsumerWidget {
  const WorkorderDetailPage({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(workorderDetailProvider(id));
    final myPic = ref.watch(authControllerProvider).value?.picDescription;

    return Scaffold(
      appBar: AppBar(title: Text('WO $id')),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(apiErrorMessage(e))),
        data: (wo) => RefreshIndicator(
          onRefresh: () => ref.refresh(workorderDetailProvider(id).future),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _Section(
                children: [
                  Text(
                    wo.description,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      wo.isReported
                          ? SoftBadge('Sudah Report (${wo.reportCount})',
                              color: ApmColors.success)
                          : const SoftBadge('Belum Report', color: ApmColors.warning),
                      if (wo.confirmationStatus == 'CNF')
                        const SoftBadge('CNF', color: ApmColors.success),
                      if (wo.confirmationStatus == 'PCNF')
                        const SoftBadge('PCNF', color: ApmColors.warning),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Divider(),
                  _Row('No. Workorder', wo.number),
                  _Row('Notification', wo.notification),
                  _Row('Maint. Plan', wo.maintenancePlan),
                  _Row('Equipment', wo.equipmentTag),
                  _Row('Nama Equipment', wo.equipmentName),
                  _Row('Plant', wo.plant),
                  _Row('Section', wo.section),
                  _Row('Work Center', wo.workcenter),
                  _Row('Status SAP', wo.sapStatus),
                  _Row('Basic Start', wo.basicStart),
                  _Row('Basic Finish', wo.basicFinish),
                ],
              ),
              const SizedBox(height: 16),
              _Title('Operasi (${wo.operations.length})'),
              _Section(
                padding: EdgeInsets.zero,
                children: [
                  if (wo.operations.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Tidak ada operasi.',
                          style: TextStyle(color: ApmColors.muted)),
                    ),
                  for (final (i, op) in wo.operations.indexed) ...[
                    if (i > 0) const Divider(),
                    ListTile(
                      dense: true,
                      leading: Text(op.activity,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      title: Text(op.shortText),
                      subtitle: Text([
                        if (op.duration != null) op.duration!,
                        if (op.pic != null) 'PIC ${op.pic}',
                        if (op.confirmed) 'Terkonfirmasi',
                      ].join(' · ')),
                      // Web (Workorder/Index.vue): Report hanya bila pic operation = PIC user;
                      // label "Lihat Report" bila WO sudah punya report.
                      trailing: _ReportButton(
                        label: wo.hasReport ? 'Lihat Report' : 'Report',
                        enabled: op.pic != null && op.pic == myPic,
                        onPressed: () async {
                          final saved = await Navigator.of(context).push<bool>(
                            MaterialPageRoute(
                              builder: (_) => ConfirmationPage(
                                workOrder: wo.number,
                                operationId: op.id,
                              ),
                            ),
                          );
                          if (saved == true) ref.invalidate(workorderDetailProvider(id));
                        },
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              _Title('Report (${wo.reports.length})'),
              _Section(
                padding: EdgeInsets.zero,
                children: [
                  if (wo.reports.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Belum ada report.',
                          style: TextStyle(color: ApmColors.muted)),
                    ),
                  for (final (i, r) in wo.reports.indexed) ...[
                    if (i > 0) const Divider(),
                    ListTile(
                      dense: true,
                      title: Text(r['no_reg']?.toString() ?? '-'),
                      subtitle: Text([r['type_report'], r['date']]
                          .whereType<Object>()
                          .join(' · ')),
                      trailing: r['is_unsafe_condition'] == true
                          ? const SoftBadge('UC', color: ApmColors.danger)
                          : null,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          color: ApmColors.muted,
          fontSize: 11,
          letterSpacing: 1,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.children, this.padding = const EdgeInsets.all(16)});

  final List<Widget> children;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: padding,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(color: ApmColors.muted, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              (value == null || value!.isEmpty) ? '-' : value!,
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportButton extends StatelessWidget {
  const _ReportButton({required this.label, required this.enabled, required this.onPressed});

  final String label;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonal(
      style: FilledButton.styleFrom(
        // Tema global memberi FilledButton lebar tak hingga (Size.fromHeight) —
        // di trailing ListTile itu membuat layout gagal.
        minimumSize: const Size(0, 36),
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 12),
      ),
      onPressed: enabled ? onPressed : null,
      child: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }
}
