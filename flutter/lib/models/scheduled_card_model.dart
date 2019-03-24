import 'dart:async';
import 'dart:core';
import 'dart:math';

import 'package:delern_flutter/models/base/database_observable_list.dart';
import 'package:delern_flutter/models/base/keyed_list_item.dart';
import 'package:delern_flutter/models/base/model.dart';
import 'package:delern_flutter/models/base/transaction.dart';
import 'package:delern_flutter/models/card_model.dart';
import 'package:delern_flutter/models/card_reply_model.dart';
import 'package:delern_flutter/models/deck_model.dart';
import 'package:delern_flutter/remote/error_reporting.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:meta/meta.dart';

@immutable
class CardAndScheduledCard {
  final CardModel card;
  final ScheduledCardModel scheduledCard;
  const CardAndScheduledCard(this.card, this.scheduledCard);
}

@immutable
class ScheduledCardsListModel implements KeyedListItem {
  final String key;
  final List<ScheduledCardModel> scheduledCards;

  const ScheduledCardsListModel({
    @required this.key,
    @required this.scheduledCards,
  })  : assert(key != null),
        assert(scheduledCards != null);
}

class ScheduledCardModel implements Model {
  static const levelDurations = [
    Duration(hours: 4),
    Duration(days: 1),
    Duration(days: 2),
    Duration(days: 5),
    Duration(days: 14),
    Duration(days: 30),
    Duration(days: 60),
  ];

  String uid;
  String deckKey;
  String key;
  int level;
  DateTime repeatAt;

  ScheduledCardModel({@required this.deckKey, @required this.uid})
      : assert(deckKey != null),
        assert(uid != null) {
    level = 0;
    repeatAt = DateTime.fromMillisecondsSinceEpoch(0);
  }

  ScheduledCardModel._fromSnapshot({
    @required this.key,
    @required this.deckKey,
    @required this.uid,
    @required Map value,
  })  : assert(uid != null),
        assert(deckKey != null),
        assert(key != null) {
    if (value == null) {
      key = null;
      return;
    }
    try {
      level = int.parse(value['level'].toString().substring(1));
    } on FormatException catch (e, stackTrace) {
      ErrorReporting.report('ScheduledCard', e, stackTrace);
      level = 0;
    }
    repeatAt = DateTime.fromMillisecondsSinceEpoch(value['repeatAt']);
  }

  // A jutter used to calculate diverse next scheduled time for a card.
  static final _jitterRandom = Random();
  Duration _newJitter() => Duration(minutes: _jitterRandom.nextInt(180));

  static Stream<CardAndScheduledCard> next(DeckModel deck) =>
      FirebaseDatabase.instance
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
          .transform(
              StreamTransformer.fromHandlers(handleData: (event, sink) async {
        if (event.snapshot.value == null) {
          // The deck is empty. Should we offer the user to re-sync?
          sink.close();
          return;
        }

        // TODO(dotdoom): remove sorting once Flutter Firebase issue is fixed.
        // Workaround for https://github.com/flutter/flutter/issues/19389.
        List<MapEntry> allEntries = event.snapshot.value.entries.toList();
        var latestScheduledCard = (allEntries
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

        var card =
            await CardModel.get(deckKey: deck.key, key: latestScheduledCard.key)
                .first;
        var scheduledCard = ScheduledCardModel._fromSnapshot(
            uid: deck.uid,
            key: latestScheduledCard.key,
            deckKey: deck.key,
            value: latestScheduledCard.value);

        if (card.key == null) {
          // Card has been removed but we still have ScheduledCard for it.

          // card.key is used within ScheduledCard and must be set.
          card.key = latestScheduledCard.key;
          print('Removing dangling ScheduledCard ${scheduledCard.key}');
          (Transaction()..delete(scheduledCard)).commit();
          return;
        }

        sink.add(CardAndScheduledCard(card, scheduledCard));
      }));

  @override
  String get rootPath => 'learning/$uid/$deckKey';

  @override
  Map<String, dynamic> toMap(bool isNew) => {
        '$rootPath/$key': {
          'level': 'L$level',
          'repeatAt': repeatAt.toUtc().millisecondsSinceEpoch,
        }
      };

  CardReplyModel answer(bool knows, bool learnBeyondHorizon) {
    var cv = CardReplyModel((b) => b
      ..uid = uid
      ..cardKey = key
      ..deckKey = key
      ..reply = knows
      ..levelBefore = level);

    // if know==true and learnBeyondHorizon==true, the level stays the same
    if (knows && !learnBeyondHorizon) {
      level = min(level + 1, levelDurations.length - 1);
    }
    if (!knows) {
      level = 0;
    }
    repeatAt = DateTime.now().toUtc().add(levelDurations[level] + _newJitter());
    return cv;
  }

  static DatabaseObservableList<ScheduledCardsListModel> listsForUser(
          String uid) =>
      DatabaseObservableList(
          query: FirebaseDatabase.instance
              .reference()
              .child('learning')
              .child(uid),
          snapshotParser: (deckKey, scheduledCardsOfDeck) {
            Map value = scheduledCardsOfDeck ?? {};
            return ScheduledCardsListModel(
                key: deckKey,
                scheduledCards: List.unmodifiable(value.entries
                    .map((entry) => ScheduledCardModel._fromSnapshot(
                          key: entry.key,
                          deckKey: deckKey,
                          uid: uid,
                          value: entry.value,
                        ))));
          },
          fetchFullValueFirst: false,
          ordered: false);
}
