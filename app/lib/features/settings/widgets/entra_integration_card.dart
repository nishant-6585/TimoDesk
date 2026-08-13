import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme.dart';
import '../../staff/providers/staff_list_provider.dart';
import '../providers/entra_provider.dart';

/// Settings card: Microsoft Entra ID (Azure AD) directory + photo sync.
///
/// Read-only status mirror — credentials/config live in the spine's .env and
/// never reach this app. Offers "Sync now" and shows the last run's summary so
/// the front-desk admin can see what the directory import did.
class EntraIntegrationCard extends ConsumerStatefulWidget {
  const EntraIntegrationCard({super.key});

  @override
  ConsumerState<EntraIntegrationCard> createState() => _EntraIntegrationCardState();
}

class _EntraIntegrationCardState extends ConsumerState<EntraIntegrationCard> {
  bool _syncing = false;

  Future<void> _syncNow() async {
    setState(() => _syncing = true);
    try {
      final s = await entraSyncNow();
      ref.invalidate(entraStatusProvider);
      ref.invalidate(staffListProvider); // synced staff show up immediately
      if (!mounted) return;
      final photos = s['photos'] as Map<String, dynamic>?;
      // Read counters defensively: the summary is built server-side, and a
      // missing key here would throw inside the success path and surface a
      // completed sync as "Entra sync failed".
      int n(String k) => (photos?[k] as num?)?.toInt() ?? 0;
      final line = photos == null
          ? '${s['fetched']} users (${s['mode']}) — photo import off'
          : '${s['fetched']} users (${s['mode']}) · ${n('embedded')} photos embedded, '
              '${n('rejected_quality') + n('rejected_multi_face')} rejected, '
              '${n('collisions')} collisions';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Entra sync done: $line')));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Entra sync failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusAsync = ref.watch(entraStatusProvider);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [MikeeColors.cardTop, MikeeColors.cardBottom]),
          border: Border.all(color: MikeeColors.border),
          borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('MICROSOFT ENTRA ID',
              style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.12,
                  color: MikeeColors.textSecondary)),
          const Spacer(),
          InkWell(
            onTap: () => ref.invalidate(entraStatusProvider),
            child: Row(children: [
              const Icon(Icons.refresh, size: 13, color: MikeeColors.textMuted),
              const SizedBox(width: 3),
              Text('Refresh',
                  style: GoogleFonts.inter(fontSize: 11, color: MikeeColors.textMuted)),
            ]),
          ),
        ]),
        const SizedBox(height: 4),
        Text('Active Directory staff + photo sync. Configured in the spine\'s .env '
            '(tenant, app registration, consent group) — see docs/ENTRA_ID_INTEGRATION_PLAN.md.',
            style: GoogleFonts.inter(fontSize: 11, color: MikeeColors.textMuted)),
        const SizedBox(height: 14),
        statusAsync.when(
          loading: () => const Center(
              child: Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                      height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)))),
          error: (e, _) => Text('Status unavailable: $e',
              style: GoogleFonts.inter(fontSize: 12, color: Colors.orange)),
          data: (s) => _buildStatus(s),
        ),
      ]),
    );
  }

  Widget _buildStatus(EntraStatus s) {
    if (!s.configured) {
      return Row(children: [
        const Icon(Icons.link_off, size: 16, color: Colors.orange),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
              'Not configured. Set ENTRA_TENANT_ID / ENTRA_CLIENT_ID / ENTRA_CLIENT_SECRET '
              'in the spine\'s .env to enable.',
              style: GoogleFonts.inter(fontSize: 12, color: MikeeColors.textSecondary)),
        ),
      ]);
    }

    final secretDays = s.secretDaysLeft;
    final rows = <Widget>[
      _statusRow(
        Icons.check_circle,
        MikeeColors.success,
        'Connected to tenant',
      ),
      _statusRow(
        s.consentMode == 'all' || s.consentGroupSet ? Icons.verified_user : Icons.gpp_bad,
        s.consentMode == 'all' || s.consentGroupSet ? MikeeColors.success : Colors.orange,
        s.consentMode == 'all'
            ? 'Photo consent: ALL employees (DPO-asserted lawful basis)'
            : s.consentGroupSet
                ? 'Photo consent: security-group members only'
                : 'Photo import OFF — no consent group configured (ENTRA_CONSENT_GROUP_ID)',
      ),
      _statusRow(
        Icons.schedule,
        MikeeColors.textSecondary,
        s.syncIntervalMin > 0
            ? 'Scheduled every ${s.syncIntervalMin >= 60 ? '${(s.syncIntervalMin / 60).toStringAsFixed(s.syncIntervalMin % 60 == 0 ? 0 : 1)} h' : '${s.syncIntervalMin} min'}'
                '${s.nextRunAt != null ? ' · next ${_ago(s.nextRunAt!, future: true)}' : ''}'
            : 'Manual sync only (ENTRA_SYNC_INTERVAL_MIN=0)',
      ),
      _statusRow(
        Icons.auto_delete_outlined,
        MikeeColors.textSecondary,
        s.offboardPurgeDays > 0
            ? 'Offboarded staff: photo embeddings auto-purged after ${s.offboardPurgeDays} days'
            : 'Offboarding auto-purge disabled',
      ),
    ];

    if (secretDays != null && secretDays < 60) {
      rows.add(_statusRow(
        Icons.warning_amber,
        secretDays < 14 ? Colors.redAccent : Colors.orange,
        secretDays < 0
            ? 'Client secret EXPIRED (${s.secretExpires}) — sync will fail until rotated'
            : 'Client secret expires in $secretDays days (${s.secretExpires})',
      ));
    }

    if (s.lastRunAt != null) {
      final sum = s.lastSummary;
      final photos = sum?['photos'] as Map<String, dynamic>?;
      rows.add(_statusRow(
        s.lastRunOk == true ? Icons.history : Icons.error_outline,
        s.lastRunOk == true ? MikeeColors.textSecondary : Colors.redAccent,
        s.lastRunOk == true
            ? 'Last sync ${_ago(s.lastRunAt!)}: ${sum?['fetched']} users (${sum?['mode']})'
                '${photos != null ? ' · ${photos['embedded']} photos embedded, ${photos['collisions']} collisions' : ''}'
            : 'Last sync ${_ago(s.lastRunAt!)} FAILED: ${s.lastRunError}',
      ));
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ...rows,
      const SizedBox(height: 14),
      SizedBox(
        width: double.infinity,
        height: 40,
        child: ElevatedButton.icon(
          onPressed: _syncing ? null : _syncNow,
          icon: _syncing
              ? const SizedBox(
                  height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.sync, size: 16),
          label: Text(_syncing ? 'Syncing…' : 'Sync now',
              style: GoogleFonts.inter(fontSize: 12)),
          style: ElevatedButton.styleFrom(
              backgroundColor: MikeeColors.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
        ),
      ),
    ]);
  }

  Widget _statusRow(IconData icon, Color color, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 8),
          Expanded(
              child: Text(text,
                  style: GoogleFonts.inter(fontSize: 12, color: MikeeColors.textSecondary))),
        ]),
      );

  String _ago(DateTime t, {bool future = false}) {
    final d = future ? t.difference(DateTime.now()) : DateTime.now().difference(t);
    final mins = d.inMinutes;
    final txt = mins < 1
        ? 'moments'
        : mins < 60
            ? '$mins min'
            : d.inHours < 24
                ? '${d.inHours} h'
                : '${d.inDays} d';
    return future ? 'in $txt' : '$txt ago';
  }
}
