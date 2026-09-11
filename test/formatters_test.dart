import 'package:connectcall/core/utils/formatters.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Formatters.duration', () {
    test('formats under an hour as mm:ss', () {
      expect(Formatters.duration(Duration.zero), '00:00');
      expect(Formatters.duration(const Duration(seconds: 9)), '00:09');
      expect(Formatters.duration(const Duration(seconds: 90)), '01:30');
      expect(Formatters.duration(const Duration(minutes: 59, seconds: 59)),
          '59:59');
    });

    test('adds hours once past an hour', () {
      expect(Formatters.duration(const Duration(seconds: 3661)), '1:01:01');
    });
  });

  group('Formatters.initials', () {
    test('uses first and last name', () {
      expect(Formatters.initials('Sarah Johnson'), 'SJ');
      expect(Formatters.initials('Ada Byron King'), 'AK');
    });

    test('handles a single name, stray spaces and blanks', () {
      expect(Formatters.initials('sarah'), 'S');
      expect(Formatters.initials('  john   smith  '), 'JS');
      expect(Formatters.initials('   '), '?');
    });
  });

  group('Formatters.callTimestamp', () {
    final now = DateTime.now();
    final todayNoon = DateTime(now.year, now.month, now.day, 12);

    test('labels today and yesterday relatively', () {
      expect(Formatters.callTimestamp(todayNoon), startsWith('Today, '));
      expect(
        Formatters.callTimestamp(todayNoon.subtract(const Duration(days: 1))),
        startsWith('Yesterday, '),
      );
    });

    test('includes the clock time', () {
      expect(Formatters.callTimestamp(todayNoon), 'Today, 12:00 PM');
    });
  });

  group('Formatters.daySection', () {
    test('groups by relative day', () {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day, 9);
      expect(Formatters.daySection(today), 'Today');
      expect(Formatters.daySection(today.subtract(const Duration(days: 1))),
          'Yesterday');
    });
  });
}
