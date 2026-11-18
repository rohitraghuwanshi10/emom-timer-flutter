import 'package:flutter_test/flutter_test.dart';
import 'package:emom_timer_flutter/services/sync_service.dart';

void main() {
  group('hrrUploadFields', () {
    test('nothing to push while recovery is still running', () {
      final local = {
        'hrr_1min': null,
        'hrr_2min': null,
        'recovery_duration_sec': null,
      };
      expect(SyncService.hrrUploadFields(local, {}), isEmpty);
    });

    test('pushes finished recovery missing remotely', () {
      final local = {
        'hrr_1min': 28,
        'hrr_2min': 41,
        'recovery_duration_sec': 120,
      };
      final remote = {
        'hrr_1min': null,
        'hrr_2min': null,
        'recovery_duration_sec': null,
      };
      expect(SyncService.hrrUploadFields(local, remote), {
        'hrr_1min': 28,
        'hrr_2min': 41,
        'recovery_duration_sec': 120,
      });
    });

    test('pushes nothing once remote matches', () {
      final local = {
        'hrr_1min': 28,
        'hrr_2min': 41,
        'recovery_duration_sec': 120,
      };
      expect(SyncService.hrrUploadFields(local, Map.of(local)), isEmpty);
    });

    test('upgrades a 1-minute partial result to the full 2-minute result', () {
      final local = {
        'hrr_1min': 28,
        'hrr_2min': 41,
        'recovery_duration_sec': 120,
      };
      final remote = {
        'hrr_1min': 28,
        'hrr_2min': null,
        'recovery_duration_sec': 60,
      };
      expect(SyncService.hrrUploadFields(local, remote), {
        'hrr_2min': 41,
        'recovery_duration_sec': 120,
      });
    });

    test('recovery stopped early: pushes duration without inventing HRR', () {
      final local = {
        'hrr_1min': null,
        'hrr_2min': null,
        'recovery_duration_sec': 35,
      };
      expect(SyncService.hrrUploadFields(local, {}), {
        'recovery_duration_sec': 35,
      });
    });
  });

  group('hrrDownloadFields', () {
    test('pulls recovery recorded on another device', () {
      final local = {
        'hrr_1min': null,
        'hrr_2min': null,
        'recovery_duration_sec': null,
      };
      final remote = {
        'hrr_1min': 30,
        'hrr_2min': 45,
        'recovery_duration_sec': 120,
      };
      expect(SyncService.hrrDownloadFields(local, remote), remote);
    });

    test('never overwrites local recovery results', () {
      final local = {
        'hrr_1min': 28,
        'hrr_2min': 41,
        'recovery_duration_sec': 120,
      };
      final remote = {
        'hrr_1min': 30,
        'hrr_2min': 45,
        'recovery_duration_sec': 120,
      };
      expect(SyncService.hrrDownloadFields(local, remote), isEmpty);
    });

    test('nothing to pull when remote has no recovery', () {
      expect(
        SyncService.hrrDownloadFields({'recovery_duration_sec': null}, {}),
        isEmpty,
      );
    });
  });

  test('hrLogToRemote keeps the recovery flag and defaults it to 0', () {
    expect(
      SyncService.hrLogToRemote({
        'id': 9,
        'workout_id': 3,
        'capture_time': 't',
        'bpm': 120,
        'zone': 'Z3',
        'is_recovery': 1,
      }),
      {'capture_time': 't', 'bpm': 120, 'zone': 'Z3', 'is_recovery': 1},
    );
    expect(
      SyncService.hrLogToRemote({
        'capture_time': 't',
        'bpm': 120,
        'zone': 'Z3',
        'is_recovery': null,
      })['is_recovery'],
      0,
    );
  });
}
