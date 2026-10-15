import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import 'workorder_filter_sheet.dart';
import 'workorder_repository.dart';

/// Daftar Workorder — sama dengan halaman web Workorder/Index (query, filter, badge).
class WorkorderListPage extends ConsumerStatefulWidget {
  const WorkorderListPage({super.key});

  @override
  ConsumerState<WorkorderListPage> createState() => _WorkorderListPageState();
}

class _WorkorderListPageState extends ConsumerState<WorkorderListPage> {
  final _scroll = ScrollController();
  final _search = TextEditingController();
  Timer? _debounce;

  final List<Workorder> _items = [];
  WoFilterState _filters = WoFilterState();
  int _page = 0;
  bool _hasMore = true;
  bool _loading = false;
  Object? _error;

  /// Request yang sedang berjalan — dibatalkan saat pencarian/filter berubah supaya
  /// request lama tidak menumpuk di server.
  CancelToken? _cancel;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 400) _loadMore();
    });
    _reload();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _cancel?.cancel();
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    _cancel?.cancel();
    setState(() {
      _items.clear();
      _page = 0;
      _hasMore = true;
      _error = null;
      _loading = false;
    });
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    final token = _cancel = CancelToken();
    setState(() => _loading = true);
    try {
      final result = await ref.read(workorderRepositoryProvider).fetch(
            page: _page + 1,
            search: _search.text.trim(),
            filters: _filters.toParams(),
            cancelToken: token,
          );
      if (!mounted || token.isCancelled) return;
      setState(() {
        _items.addAll(result.items);
        _page = result.currentPage;
        _hasMore = result.hasMore;
      });
    } catch (e) {
      if (e is DioException && CancelToken.isCancel(e)) return;
      if (mounted && !token.isCancelled) setState(() => _error = e);
    } finally {
      if (mounted && !token.isCancelled) setState(() => _loading = false);
    }
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), _reload);
  }

  Future<void> _openFilters() async {
    try {
      final defs = await ref.read(workorderFilterDefsProvider.future);
      if (!mounted) return;
      final picked = await showWorkorderFilterSheet(context, defs: defs, current: _filters);
      if (picked == null) return;
      setState(() => _filters = picked);
      _reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = _filters.activeCount;
    return Scaffold(
      appBar: AppBar(title: const Text('Workorder')),
      body: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _search,
                  onChanged: _onSearchChanged,
                  decoration: const InputDecoration(
                    hintText: 'Cari WO, notif, equipment, plant…',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Badge(
                isLabelVisible: active > 0,
                label: Text('$active'),
                child: IconButton.filledTonal(
                  onPressed: _openFilters,
                  icon: const Icon(Icons.tune),
                ),
              ),
            ]),
          ),
          const Divider(),
          Expanded(child: _buildList()),
        ],
      ),
    );
  }

  Widget _buildList() {
    if (_error != null && _items.isEmpty) {
      return _Message(
        icon: Icons.cloud_off,
        text: apiErrorMessage(_error!),
        action: TextButton(onPressed: _reload, child: const Text('Coba lagi')),
      );
    }
    if (_items.isEmpty && _loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_items.isEmpty) {
      return const _Message(icon: Icons.inbox_outlined, text: 'Data tidak ditemukan.');
    }

    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView.separated(
        controller: _scroll,
        padding: const EdgeInsets.all(16),
        itemCount: _items.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          if (i == _items.length) {
            return _loading
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : const SizedBox.shrink();
          }
          return WorkorderCard(_items[i]);
        },
      ),
    );
  }
}

class WorkorderCard extends StatelessWidget {
  const WorkorderCard(this.wo, {super.key});

  final Workorder wo;

  static final _date = DateFormat('EEE, d MMM yyyy', 'id_ID');

  String _fmt(String? d) {
    final p = DateTime.tryParse(d ?? '');
    return p == null ? '-' : _date.format(p);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(color: ApmColors.muted);

    // Badge sama dengan kolom pertama tabel web.
    final badges = <Widget>[
      if (wo.isBacklog) const SoftBadge('Backlog', color: ApmColors.muted),
      if (wo.isToday) const SoftBadge('Today', color: ApmColors.info),
      if (wo.isReported) const SoftBadge('Reported', color: ApmColors.success),
      if (wo.confirmationStatus == 'CNF') const SoftBadge('Confirmed', color: ApmColors.success),
      if (wo.confirmationStatus == 'PCNF') const SoftBadge('PCNF', color: ApmColors.warning),
      wo.isPpm
          ? const SoftBadge('PPM', color: ApmColors.info)
          : const SoftBadge('Corrective', color: ApmColors.danger),
      if (wo.allNotExecuted) const SoftBadge('Not-Executed', color: ApmColors.danger),
    ];

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/workorder/${wo.number}'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(spacing: 6, runSpacing: 6, children: badges),
              const SizedBox(height: 8),
              Row(children: [
                Text(
                  wo.number,
                  style: text.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: ApmColors.primary,
                  ),
                ),
                const SizedBox(width: 8),
                if (wo.notification != null)
                  Expanded(
                    child: Text('Notif ${wo.notification}',
                        style: muted, overflow: TextOverflow.ellipsis),
                  ),
              ]),
              if (wo.ucReportNumbers.isNotEmpty)
                Text('UC: ${wo.ucReportNumbers.join(', ')}',
                    style: const TextStyle(color: ApmColors.danger, fontSize: 12)),
              const SizedBox(height: 4),
              Text(wo.description, style: text.bodyMedium),
              const SizedBox(height: 6),
              Text(
                [wo.equipmentTag, if (wo.equipmentName != null) wo.equipmentName].join(' · '),
                style: muted,
              ),
              Text(
                [
                  if (wo.workcenterDescription != null) wo.workcenterDescription,
                  if (wo.rtta != null) 'RT/TA ${wo.rtta}',
                  if (wo.plant != null) wo.plant,
                ].join(' · '),
                style: muted,
              ),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(
                  child: Text('Start ${_fmt(wo.basicStart)}',
                      style: const TextStyle(color: ApmColors.danger, fontSize: 12)),
                ),
                Expanded(
                  child: Text('Finish ${_fmt(wo.basicFinish)}',
                      style: const TextStyle(color: ApmColors.success, fontSize: 12)),
                ),
              ]),
              const SizedBox(height: 4),
              Text(
                [
                  'PM: ${wo.sapStatus ?? '-'}',
                  if (wo.duration != null) wo.duration,
                ].join(' · '),
                style: muted,
              ),
              if (wo.readinessStatus != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Readiness: ${wo.readinessStatus}'
                  '${wo.readinessEstimate != null ? ' · Estimasi ${_fmt(wo.readinessEstimate)}' : ''}',
                  style: const TextStyle(
                      color: ApmColors.danger, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: ApmColors.muted),
            const SizedBox(height: 8),
            Text(text, textAlign: TextAlign.center),
            ?action,
          ],
        ),
      ),
    );
  }
}
