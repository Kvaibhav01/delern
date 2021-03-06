import 'dart:async';

import 'package:delern_flutter/models/base/transaction.dart';
import 'package:delern_flutter/models/card_model.dart';
import 'package:delern_flutter/models/scheduled_card_model.dart';
import 'package:delern_flutter/remote/analytics.dart';
import 'package:delern_flutter/remote/error_reporting.dart' as error_reporting;
import 'package:delern_flutter/view_models/base/screen_bloc.dart';
import 'package:meta/meta.dart';

class CardCreateUpdateBloc extends ScreenBloc {
  String _frontText;
  String _backText;
  bool _addReversedCard = false;
  String uid;
  CardModel _cardModel;
  final bool isAddOperation;
  bool _isOperationEnabled = true;

  CardCreateUpdateBloc({@required cardModel})
      : assert(cardModel != null),
        isAddOperation = cardModel.key == null {
    _cardModel = cardModel;
    _initFields();
    _initListeners();
  }

  Sink<String> get onUid => _onUidController.sink;
  final _onUidController = StreamController<String>();

  final _onSaveCardController = StreamController<void>();
  Sink<void> get onSaveCard => _onSaveCardController.sink;

  final _onFrontSideTextController = StreamController<String>();
  Sink<String> get onFrontSideText => _onFrontSideTextController.sink;

  final _onBackSideTextController = StreamController<String>();
  Sink<String> get onBackSideText => _onBackSideTextController.sink;

  final _addReversedCardController = StreamController<bool>();
  Sink<bool> get onAddReversedCard => _addReversedCardController.sink;

  final _doClearInputFieldsController = StreamController<void>();
  Stream<void> get doClearInputFields => _doClearInputFieldsController.stream;

  final _isOperationEnabledController = StreamController<bool>();
  Stream<bool> get isOperationEnabled => _isOperationEnabledController.stream;

  final _doShowConfirmationDialogController = StreamController<void>();
  Stream<void> get doShowConfirmationDialog =>
      _doShowConfirmationDialogController.stream;

  final _onDiscardChangesController = StreamController<void>();
  Sink<void> get onDiscardChanges => _onDiscardChangesController.sink;

  void _initFields() {
    _frontText = _cardModel.front ?? '';
    _backText = _cardModel.back ?? '';
  }

  void _initListeners() {
    _onSaveCardController.stream.listen((_) => _processSavingCard());
    _onFrontSideTextController.stream.listen((frontText) {
      _frontText = frontText;
      _checkOperationAvailability();
    });
    _onBackSideTextController.stream.listen((backText) {
      _backText = backText;
      _checkOperationAvailability();
    });
    _addReversedCardController.stream.listen((addReversed) {
      _addReversedCard = addReversed;
      _checkOperationAvailability();
    });
    _onUidController.stream.listen((uid) => this.uid = uid);
    _onDiscardChangesController.stream.listen((_) {
      notifyPop();
    });
  }

  Future<void> _saveCard() {
    logCardCreate(_cardModel.deckKey);
    final t = Transaction()..save(_cardModel);
    final sCard = ScheduledCardModel(deckKey: _cardModel.deckKey, uid: uid)
      ..key = _cardModel.key;
    t.save(sCard);

    if (_addReversedCard) {
      final reverse = CardModel.copyFrom(_cardModel)
        ..key = null
        ..front = _cardModel.back
        ..back = _cardModel.front;
      t.save(reverse);
      final reverseScCard =
          ScheduledCardModel(deckKey: reverse.deckKey, uid: uid)
            ..key = reverse.key;
      t.save(reverseScCard);
    }
    return t.commit();
  }

  Future<void> _disableUI(Future<void> Function() f) async {
    _isOperationEnabled = false;
    _isOperationEnabledController.add(_isOperationEnabled);
    try {
      await f();
    } finally {
      _isOperationEnabled = true;
      _isOperationEnabledController.add(_isOperationEnabled);
    }
  }

  Future<void> _processSavingCard() async {
    _cardModel
      ..front = _frontText.trim()
      ..back = _backText.trim();
    try {
      await _disableUI(_saveCard);
      if (!isAddOperation) {
        notifyPop();
        return;
      }
      _clearCard();
      if (_addReversedCard) {
        showMessage(locale.cardAndReversedAddedUserMessage);
      } else {
        showMessage(locale.cardAddedUserMessage);
      }
      _doClearInputFieldsController.add(null);
    } catch (e, stackTrace) {
      error_reporting.report('saveCard', e, stackTrace);
      notifyErrorOccurred(e);
    }
  }

  void _clearCard() {
    // Unset Card key so that we create a new one.
    _cardModel.key = null;
  }

  bool _isCardValid() => _addReversedCard
      ? _frontText.trim().isNotEmpty && _backText.trim().isNotEmpty
      : _frontText.trim().isNotEmpty;

  void _checkOperationAvailability() {
    _isOperationEnabledController.add(_isOperationEnabled && _isCardValid());
  }

  @override
  Future<bool> userClosesScreen() async {
    _doShowConfirmationDialogController.add(null);
    return Future.value(false);
  }

  @override
  void dispose() {
    _onSaveCardController.close();
    _doClearInputFieldsController.close();
    _onFrontSideTextController.close();
    _onBackSideTextController.close();
    _isOperationEnabledController.close();
    _addReversedCardController.close();
    _doShowConfirmationDialogController.close();
    _onUidController.close();
    _onDiscardChangesController.close();
    super.dispose();
  }
}
