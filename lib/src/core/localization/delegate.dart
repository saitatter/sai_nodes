import 'dart:ui';

import 'package:sai_nodes/src/core/localization/ar.dart';
import 'package:sai_nodes/src/core/localization/de.dart';
import 'package:sai_nodes/src/core/localization/en.dart';
import 'package:sai_nodes/src/core/localization/es.dart';
import 'package:sai_nodes/src/core/localization/fr.dart';
import 'package:sai_nodes/src/core/localization/it.dart';
import 'package:sai_nodes/src/core/localization/ja.dart';
import 'package:sai_nodes/src/core/localization/ko.dart';
import 'package:sai_nodes/src/core/localization/ru.dart';
import 'package:sai_nodes/src/core/localization/zh.dart';
import 'package:flutter/widgets.dart';

/// An abstract class that defines the localizations for the Node Editor.
abstract class NodeEditorLocalizations {
  final Locale locale;

  NodeEditorLocalizations(this.locale);

  static NodeEditorLocalizations of(BuildContext? context) {
    if (context == null) return _fallback;

    final loc = Localizations.of<NodeEditorLocalizations>(
      context,
      NodeEditorLocalizations,
    );

    return loc ?? _fallback;
  }

  static final NodeEditorLocalizations _fallback =
      switch (PlatformDispatcher.instance.locale.languageCode) {
    'it' => NodeEditorLocalizationsIt(const Locale('it')),
    'fr' => NodeEditorLocalizationsFr(const Locale('fr')),
    'es' => NodeEditorLocalizationsEs(const Locale('es')),
    'de' => NodeEditorLocalizationsDe(const Locale('de')),
    'ja' => NodeEditorLocalizationsJa(const Locale('ja')),
    'zh' => NodeEditorLocalizationsZh(const Locale('zh')),
    'ko' => NodeEditorLocalizationsKo(const Locale('ko')),
    'ru' => NodeEditorLocalizationsRu(const Locale('ru')),
    'ar' => NodeEditorLocalizationsAr(const Locale('ar')),
    _ => NodeEditorLocalizationsEn(const Locale('en')),
  };

  String get closeAction;
  String get addNodeAction;
  String get deleteNodeAction;
  String get centerViewAction;
  String get resetZoomAction;
  String get createNodeAction;
  String get copySelectionAction;
  String get pasteSelectionAction;
  String get cutSelectionAction;
  String get projectLabel;
  String get undoAction;
  String get redoAction;
  String get newProjectAction;
  String get saveProjectAction;
  String get openProjectAction;
  String get seeNodeDescriptionAction;
  String get collapseNodeAction;
  String get expandNodeAction;
  String get cutLinksAction;
  String get editorMenuLabel;
  String get nodeMenuLabel;
  String get portMenuLabel;
  String failedToCopySelectionErrorMsg(String e);
  String get selectionCopiedSuccessfullyMsg;
  String failedToPasteSelectionErrorMsg(String e);
  String failedToSaveProjectErrorMsg(String e);
  String get projectSavedSuccessfullyMsg;
  String failedToLoadProjectErrorMsg(String e);
  String get projectLoadedSuccessfullyMsg;
  String get newProjectCreatedSuccessfullyMsg;
  String failedToExecuteNodeErrorMsg(String e);
}

/// A delegate that provides localized strings for the Node Editor.
class NodeEditorLocalizationsDelegate
    extends LocalizationsDelegate<NodeEditorLocalizations> {
  const NodeEditorLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => [
        'en',
        'it',
        'fr',
        'es',
        'de',
        'ja',
        'zh',
        'ko',
        'ru',
        'ar',
      ].contains(locale.languageCode);

  @override
  Future<NodeEditorLocalizations> load(Locale locale) async {
    return switch (locale.languageCode) {
      'en' => NodeEditorLocalizationsEn(locale),
      'it' => NodeEditorLocalizationsIt(locale),
      'fr' => NodeEditorLocalizationsFr(locale),
      'es' => NodeEditorLocalizationsEs(locale),
      'de' => NodeEditorLocalizationsDe(locale),
      'ja' => NodeEditorLocalizationsJa(locale),
      'zh' => NodeEditorLocalizationsZh(locale),
      'ko' => NodeEditorLocalizationsKo(locale),
      'ru' => NodeEditorLocalizationsRu(locale),
      'ar' => NodeEditorLocalizationsAr(locale),
      _ => NodeEditorLocalizationsEn(locale)
    };
  }

  @override
  bool shouldReload(covariant LocalizationsDelegate old) => false;
}
