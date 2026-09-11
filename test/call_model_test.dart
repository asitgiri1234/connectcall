import 'package:connectcall/models/call_history_entry.dart';
import 'package:connectcall/models/call_model.dart';
import 'package:connectcall/widgets/history_tile.dart';
import 'package:flutter_test/flutter_test.dart';

CallModel _call({
  CallStatus status = CallStatus.ended,
  DateTime? createdAt,
  DateTime? connectedAt,
  DateTime? endedAt,
}) {
  return CallModel(
    callId: 'call1',
    callerId: 'alice',
    callerName: 'Alice',
    receiverId: 'bob',
    receiverName: 'Bob',
    type: CallType.video,
    status: status,
    channelName: 'call_call1',
    createdAt: createdAt,
    connectedAt: connectedAt,
    endedAt: endedAt,
  );
}

void main() {
  group('CallStatus', () {
    test('unknown or missing values fall back to failed, not a crash', () {
      expect(CallStatus.fromName('something-new'), CallStatus.failed);
      expect(CallStatus.fromName(null), CallStatus.failed);
      expect(CallStatus.fromName('ringing'), CallStatus.ringing);
    });

    test('every ending outcome is terminal, and nothing else is', () {
      const terminal = {
        CallStatus.ended,
        CallStatus.rejected,
        CallStatus.missed,
        CallStatus.busy,
        CallStatus.failed,
        CallStatus.disconnected,
      };
      for (final status in CallStatus.values) {
        expect(status.isTerminal, terminal.contains(status),
            reason: '${status.name}.isTerminal');
      }
    });

    test('ringing and active are disjoint phases', () {
      for (final status in CallStatus.values) {
        expect(status.isRinging && status.isActive, isFalse,
            reason: status.name);
      }
    });
  });

  group('CallModel', () {
    test('survives a round trip through the database map', () {
      final original = _call(
        createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
        connectedAt: DateTime.fromMillisecondsSinceEpoch(5000),
        endedAt: DateTime.fromMillisecondsSinceEpoch(65000),
      );
      final copy = CallModel.fromMap('call1', original.toMap());
      expect(copy.callerId, 'alice');
      expect(copy.receiverName, 'Bob');
      expect(copy.type, CallType.video);
      expect(copy.status, CallStatus.ended);
      expect(copy.duration, const Duration(seconds: 60));
    });

    test('names the other party from either side', () {
      final call = _call();
      expect(call.otherPartyName('alice'), 'Bob');
      expect(call.otherPartyName('bob'), 'Alice');
    });
  });

  group('CallHistoryEntry.pairFor', () {
    final created = DateTime.fromMillisecondsSinceEpoch(1000000);

    test('mirrors one call into an outgoing and an incoming entry', () {
      final pair = CallHistoryEntry.pairFor(_call(createdAt: created));

      expect(pair.caller.direction, CallDirection.outgoing);
      expect(pair.caller.peerId, 'bob');
      expect(pair.receiver.direction, CallDirection.incoming);
      expect(pair.receiver.peerId, 'alice');
      // Both participants must agree on when the call happened.
      expect(pair.caller.startedAt, pair.receiver.startedAt);
    });

    test('measures talk time from connection, not from placing the call', () {
      final pair = CallHistoryEntry.pairFor(_call(
        createdAt: created,
        connectedAt: created.add(const Duration(seconds: 20)), // 20s ringing
        endedAt: created.add(const Duration(seconds: 170)),
      ));
      expect(pair.caller.duration, const Duration(seconds: 150));
    });

    test('a call that never connected lasted zero seconds', () {
      final pair = CallHistoryEntry.pairFor(_call(
        status: CallStatus.missed,
        createdAt: created,
        endedAt: created.add(const Duration(seconds: 45)),
      ));
      expect(pair.caller.duration, Duration.zero);
      expect(pair.caller.wasAnswered, isFalse);
    });

    test('only the callee sees a missed call; the caller sees no answer', () {
      final pair = CallHistoryEntry.pairFor(
          _call(status: CallStatus.missed, createdAt: created));
      expect(pair.receiver.isMissed, isTrue);
      expect(pair.receiver.outcomeLabel, 'Missed');
      expect(pair.caller.isMissed, isFalse);
      expect(pair.caller.outcomeLabel, 'No answer');
    });

    test('writes exactly the keys the database rules allow', () {
      final entry = CallHistoryEntry.pairFor(_call(createdAt: created)).caller;
      expect(entry.toMap().keys.toSet(), {
        'peerId',
        'peerName',
        'peerPhotoUrl',
        'type',
        'direction',
        'status',
        'startedAt',
        'durationSeconds',
      });
    });
  });

  group('groupHistoryByDay', () {
    test('inserts a header before each new day', () {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day, 12);
      CallHistoryEntry at(DateTime t) => CallHistoryEntry(
            callId: t.toIso8601String(),
            peerId: 'p',
            peerName: 'P',
            type: CallType.audio,
            direction: CallDirection.outgoing,
            status: CallStatus.ended,
            startedAt: t,
            duration: Duration.zero,
          );

      final items = groupHistoryByDay([
        at(today.add(const Duration(minutes: 5))),
        at(today),
        at(today.subtract(const Duration(days: 1))),
      ]);

      expect(items.whereType<String>().toList(), ['Today', 'Yesterday']);
      expect(items.first, 'Today');
      expect(items.length, 5); // 2 headers + 3 entries
    });
  });
}
