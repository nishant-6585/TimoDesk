import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mikee_admin/features/settings/providers/entra_provider.dart';
import 'package:mikee_admin/features/settings/widgets/entra_integration_card.dart';

/// Pumps the card with a stubbed [entraStatusProvider] so the render states can
/// be asserted without a spine. The card is otherwise only reachable through
/// Settings, which needs the whole app shell.
Future<void> pumpCard(WidgetTester tester, EntraStatus status) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [entraStatusProvider.overrideWith((ref) async => status)],
      child: const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: EntraIntegrationCard())),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('EntraStatus.fromJson', () {
    test('parses the real not-configured payload from GET /entra/status', () {
      // Captured verbatim from `curl localhost:4000/entra/status` against the
      // spine on this branch — pins the client/server contract.
      final json = jsonDecode(
        '{"ok":true,"configured":false,"tenant_set":false,"consent_mode":"group",'
        '"consent_group_set":false,"sync_interval_min":360,"offboard_purge_days":30,'
        '"secret_expires":null,"last_run":null,"next_run_at":null}',
      ) as Map<String, dynamic>;

      final s = EntraStatus.fromJson(json);

      expect(s.configured, isFalse);
      expect(s.consentMode, 'group');
      expect(s.consentGroupSet, isFalse);
      expect(s.syncIntervalMin, 360);
      expect(s.offboardPurgeDays, 30);
      expect(s.secretExpires, isNull);
      expect(s.lastRunAt, isNull);
      expect(s.nextRunAt, isNull);
      expect(s.secretDaysLeft, isNull);
    });

    test('parses a configured payload with a last run summary', () {
      final json = jsonDecode(
        '{"ok":true,"configured":true,"tenant_set":true,"consent_mode":"group",'
        '"consent_group_set":true,"sync_interval_min":360,"offboard_purge_days":30,'
        '"secret_expires":"2027-01-01","next_run_at":"2026-08-13T18:00:00.000Z",'
        '"last_run":{"at":"2026-08-13T12:00:00.000Z","ok":true,'
        '"summary":{"fetched":42,"mode":"delta","photos":{"embedded":7,"collisions":1}}}}',
      ) as Map<String, dynamic>;

      final s = EntraStatus.fromJson(json);

      expect(s.configured, isTrue);
      expect(s.consentGroupSet, isTrue);
      expect(s.lastRunOk, isTrue);
      expect(s.lastRunAt, isNotNull);
      expect(s.nextRunAt, isNotNull);
      expect(s.lastSummary?['fetched'], 42);
      expect((s.lastSummary?['photos'] as Map<String, dynamic>)['embedded'], 7);
    });

    test('secretDaysLeft counts down and goes negative once expired', () {
      final future = DateTime.now().add(const Duration(days: 30));
      final past = DateTime.now().subtract(const Duration(days: 5));

      EntraStatus withExpiry(String iso) => EntraStatus(
            configured: true,
            consentMode: 'group',
            consentGroupSet: true,
            syncIntervalMin: 360,
            offboardPurgeDays: 30,
            secretExpires: iso,
          );

      expect(withExpiry(future.toIso8601String()).secretDaysLeft, inInclusiveRange(28, 30));
      expect(withExpiry(past.toIso8601String()).secretDaysLeft, lessThan(0));
      expect(withExpiry('not-a-date').secretDaysLeft, isNull);
    });
  });

  group('EntraIntegrationCard', () {
    testWidgets('renders the not-configured state with the setup hint', (tester) async {
      await pumpCard(
        tester,
        EntraStatus(
          configured: false,
          consentMode: 'group',
          consentGroupSet: false,
          syncIntervalMin: 360,
          offboardPurgeDays: 30,
        ),
      );

      expect(find.text('MICROSOFT ENTRA ID'), findsOneWidget);
      expect(find.textContaining('Not configured'), findsOneWidget);
      expect(find.textContaining('ENTRA_TENANT_ID'), findsOneWidget);
      // Nothing to sync until the tenant is wired up.
      expect(find.text('Sync now'), findsNothing);
    });

    testWidgets('configured without a consent group shows photo import OFF', (tester) async {
      await pumpCard(
        tester,
        EntraStatus(
          configured: true,
          consentMode: 'group',
          consentGroupSet: false,
          syncIntervalMin: 360,
          offboardPurgeDays: 30,
        ),
      );

      expect(find.textContaining('Photo import OFF'), findsOneWidget);
      expect(find.textContaining('ENTRA_CONSENT_GROUP_ID'), findsOneWidget);
      expect(find.text('Sync now'), findsOneWidget);
    });

    testWidgets('consented + scheduled state reads back the schedule', (tester) async {
      await pumpCard(
        tester,
        EntraStatus(
          configured: true,
          consentMode: 'group',
          consentGroupSet: true,
          syncIntervalMin: 360,
          offboardPurgeDays: 30,
        ),
      );

      expect(find.textContaining('security-group members only'), findsOneWidget);
      expect(find.textContaining('Scheduled every 6 h'), findsOneWidget);
      expect(find.textContaining('auto-purged after 30 days'), findsOneWidget);
    });

    testWidgets('warns when the client secret is close to expiry', (tester) async {
      await pumpCard(
        tester,
        EntraStatus(
          configured: true,
          consentMode: 'group',
          consentGroupSet: true,
          syncIntervalMin: 0,
          offboardPurgeDays: 30,
          secretExpires: DateTime.now().add(const Duration(days: 10)).toIso8601String(),
        ),
      );

      expect(find.textContaining('Client secret expires in'), findsOneWidget);
      // 0 = manual-only, and the card should say so rather than show a schedule.
      expect(find.textContaining('Manual sync only'), findsOneWidget);
    });

    testWidgets('shows a failed last run with its error', (tester) async {
      await pumpCard(
        tester,
        EntraStatus(
          configured: true,
          consentMode: 'all',
          consentGroupSet: false,
          syncIntervalMin: 360,
          offboardPurgeDays: 0,
          lastRunAt: DateTime.now().subtract(const Duration(minutes: 5)),
          lastRunOk: false,
          lastRunError: 'AADSTS7000215: invalid client secret',
        ),
      );

      expect(find.textContaining('FAILED'), findsOneWidget);
      expect(find.textContaining('AADSTS7000215'), findsOneWidget);
      expect(find.textContaining('ALL employees'), findsOneWidget);
      expect(find.textContaining('Offboarding auto-purge disabled'), findsOneWidget);
    });
  });
}
