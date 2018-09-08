import 'dart:async';
import 'dart:core';
import 'dart:math';

import 'package:firebase_database/firebase_database.dart';
import 'package:meta/meta.dart';

import '../remote/error_reporting.dart';
import 'base/keyed_list.dart';
import 'base/model.dart';
import 'base/transaction.dart';
import 'card.dart';
import 'card_view.dart';
import 'deck.dart';

class ScheduledCard implements KeyedListItem, Model {
  static const levelDurations = [
    Duration(hours: 4),
    Duration(days: 1),
    Duration(days: 2),
    Duration(days: 5),
    Duration(days: 14),
    Duration(days: 30),
    Duration(days: 60),
  ];

  String get key => card.key;
  set key(_) => throw Exception('ScheduledCard key is always set via "card"');
  Card card;
  int level;
  DateTime repeatAt;

  ScheduledCard({@required this.card, this.level: 0, this.repeatAt})
      : assert(card != null) {
    repeatAt ??= DateTime.fromMillisecondsSinceEpoch(0);
  }

  ScheduledCard.fromSnapshot(snapshotValue, {@required this.card})
      : assert(card != null) {
    _parseSnapshot(snapshotValue);
  }

  void _parseSnapshot(snapshotValue) {
    if (snapshotValue == null) {
      // Assume the ScheduledCard doesn't exist anymore.
      key = null;
      return;
    }
    try {
      level = int.parse(snapshotValue['level'].toString().substring(1));
    } on FormatException catch (e, stackTrace) {
      ErrorReporting.report('ScheduledCard', e, stackTrace);
      level = 0;
    }
    repeatAt = DateTime.fromMillisecondsSinceEpoch(snapshotValue['repeatAt']);
  }

  static Stream<ScheduledCard> next(Deck deck) => FirebaseDatabase.instance
          .reference()
          .child('learning')
          .child(deck.uid)
          .child(deck.key)
          .orderByChild('repeatAt')
          // Need at least 2 because of how Firebase local cache works.
          // After we pick up the latest ScheduledCard and update it, it
          // triggers onValue twice: once with the updated ScheduledCard (most
          // likely triggered by local cache) and the second time with the next
          // ScheduledCard (fetched from the server). Doing keepSynced(true) on
          // the learning tree fixes this because local cache gets all entries.
          .limitToFirst(2)
          .onValue
          .transform(StreamTransformer.fromHandlers(
              handleData: (event, EventSink<ScheduledCard> sink) async {
        if (event.snapshot.value == null) {
          // The deck is empty. Should we offer the user to re-sync?
          sink.close();
          return;
        }

        // TODO(dotdoom): remove sorting once Flutter Firebase issue is fixed.
        // Workaround for https://github.com/flutter/flutter/issues/19389.
        var latestScheduledCard =
            ((event.snapshot.value.entries.toList() as List<MapEntry>)
                  ..sort((s1, s2) {
                    var repeatAtComparison =
                        s1.value['repeatAt'].compareTo(s2.value['repeatAt']);
                    // Sometimes repeatAt of 2 cards may be the same, which
                    // will result in unstable order. Most often this is
                    // happening to the newly added cards, which have
                    // repeatAt = 0.
                    // We mimic Firebase behavior here, which falls back to
                    // sorting lexicographically by key.
                    // TODO(dotdoom): do not set repeatAt = 0?
                    if (repeatAtComparison == 0) {
                      return s1.key.compareTo(s2.key);
                    }
                    return repeatAtComparison;
                  }))
                .first;

        var card = await Card.fetch(deck, latestScheduledCard.key);
        var scheduledCard =
            ScheduledCard.fromSnapshot(latestScheduledCard.value, card: card);

        if (card.key == null) {
          // Card has been removed but we still have ScheduledCard for it.

          // card.key is used within ScheduledCard and must be set.
          card.key = latestScheduledCard.key;
          print('Removing dangling ScheduledCard ${scheduledCard.key}');
          (Transaction()..delete(scheduledCard)).commit();
          return;
        }

        sink.add(scheduledCard);
      }));

  @override
  String get rootPath => 'learning/${card.deck.uid}/${card.deck.uid}';

  @override
  Map<String, dynamic> toMap(bool isNew) => {
        'learning/${card.deck.uid}/${card.deck.key}/$key': {
          'level': 'L$level',
          'repeatAt': repeatAt.toUtc().millisecondsSinceEpoch,
        }
      };

  CardView answer(bool knows) {
    var cv = CardView(card: card);
    cv.reply = knows;
    cv.levelBefore = level;
    if (knows) {
      level = min(level + 1, levelDurations.length - 1);
    } else {
      level = 0;
    }
    repeatAt = DateTime.now().toUtc().add(levelDurations[level]);
    return cv;
  }
}