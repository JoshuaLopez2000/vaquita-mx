import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_es.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('es')
  ];

  /// No description provided for @appTitle.
  ///
  /// In es, this message translates to:
  /// **'Vaquita MX'**
  String get appTitle;

  /// No description provided for @home.
  ///
  /// In es, this message translates to:
  /// **'Inicio'**
  String get home;

  /// No description provided for @inbox.
  ///
  /// In es, this message translates to:
  /// **'Bandeja'**
  String get inbox;

  /// No description provided for @movements.
  ///
  /// In es, this message translates to:
  /// **'Movimientos'**
  String get movements;

  /// No description provided for @contacts.
  ///
  /// In es, this message translates to:
  /// **'Contactos'**
  String get contacts;

  /// No description provided for @profile.
  ///
  /// In es, this message translates to:
  /// **'Perfil'**
  String get profile;

  /// No description provided for @newGroup.
  ///
  /// In es, this message translates to:
  /// **'Nuevo grupo'**
  String get newGroup;

  /// No description provided for @retry.
  ///
  /// In es, this message translates to:
  /// **'Reintentar'**
  String get retry;

  /// No description provided for @cancel.
  ///
  /// In es, this message translates to:
  /// **'Cancelar'**
  String get cancel;

  /// No description provided for @save.
  ///
  /// In es, this message translates to:
  /// **'Guardar'**
  String get save;

  /// No description provided for @close.
  ///
  /// In es, this message translates to:
  /// **'Cerrar'**
  String get close;

  /// No description provided for @remove.
  ///
  /// In es, this message translates to:
  /// **'Eliminar'**
  String get remove;

  /// No description provided for @addContact.
  ///
  /// In es, this message translates to:
  /// **'Agregar contacto'**
  String get addContact;

  /// No description provided for @noContactsSaved.
  ///
  /// In es, this message translates to:
  /// **'Aún no hay contactos guardados.'**
  String get noContactsSaved;

  /// No description provided for @noGroups.
  ///
  /// In es, this message translates to:
  /// **'Aún no hay grupos'**
  String get noGroups;

  /// No description provided for @noMovements.
  ///
  /// In es, this message translates to:
  /// **'Aún no hay movimientos'**
  String get noMovements;

  /// No description provided for @noExpenses.
  ///
  /// In es, this message translates to:
  /// **'Aún no hay gastos'**
  String get noExpenses;

  /// No description provided for @createGroup.
  ///
  /// In es, this message translates to:
  /// **'Crear grupo'**
  String get createGroup;

  /// No description provided for @addExpense.
  ///
  /// In es, this message translates to:
  /// **'Agregar gasto'**
  String get addExpense;

  /// No description provided for @paymentProvider.
  ///
  /// In es, this message translates to:
  /// **'Proveedor de pago'**
  String get paymentProvider;

  /// No description provided for @simulatedProvider.
  ///
  /// In es, this message translates to:
  /// **'Simulado — no se mueve dinero real'**
  String get simulatedProvider;

  /// No description provided for @signIn.
  ///
  /// In es, this message translates to:
  /// **'Iniciar sesión'**
  String get signIn;

  /// No description provided for @createAccount.
  ///
  /// In es, this message translates to:
  /// **'Crear cuenta'**
  String get createAccount;

  /// No description provided for @welcomeBack.
  ///
  /// In es, this message translates to:
  /// **'Bienvenido de nuevo'**
  String get welcomeBack;

  /// No description provided for @createYourAccount.
  ///
  /// In es, this message translates to:
  /// **'Crea tu cuenta'**
  String get createYourAccount;

  /// No description provided for @email.
  ///
  /// In es, this message translates to:
  /// **'Correo electrónico'**
  String get email;

  /// No description provided for @password.
  ///
  /// In es, this message translates to:
  /// **'Contraseña'**
  String get password;

  /// No description provided for @name.
  ///
  /// In es, this message translates to:
  /// **'Nombre'**
  String get name;

  /// No description provided for @phone.
  ///
  /// In es, this message translates to:
  /// **'Teléfono'**
  String get phone;

  /// No description provided for @groupName.
  ///
  /// In es, this message translates to:
  /// **'Nombre del grupo'**
  String get groupName;

  /// No description provided for @expenseDescription.
  ///
  /// In es, this message translates to:
  /// **'Descripción'**
  String get expenseDescription;

  /// No description provided for @amount.
  ///
  /// In es, this message translates to:
  /// **'Monto'**
  String get amount;

  /// No description provided for @you.
  ///
  /// In es, this message translates to:
  /// **'Tú'**
  String get you;

  /// No description provided for @youOwe.
  ///
  /// In es, this message translates to:
  /// **'Debes'**
  String get youOwe;

  /// No description provided for @youAreOwed.
  ///
  /// In es, this message translates to:
  /// **'Te deben'**
  String get youAreOwed;

  /// No description provided for @settledUp.
  ///
  /// In es, this message translates to:
  /// **'Saldado'**
  String get settledUp;

  /// No description provided for @accept.
  ///
  /// In es, this message translates to:
  /// **'Aceptar'**
  String get accept;

  /// No description provided for @decline.
  ///
  /// In es, this message translates to:
  /// **'Rechazar'**
  String get decline;

  /// No description provided for @language.
  ///
  /// In es, this message translates to:
  /// **'Idioma'**
  String get language;

  /// No description provided for @languageDescription.
  ///
  /// In es, this message translates to:
  /// **'Elige el idioma de la aplicación'**
  String get languageDescription;

  /// No description provided for @chooseLanguage.
  ///
  /// In es, this message translates to:
  /// **'Elegir idioma'**
  String get chooseLanguage;

  /// No description provided for @spanish.
  ///
  /// In es, this message translates to:
  /// **'Español'**
  String get spanish;

  /// No description provided for @english.
  ///
  /// In es, this message translates to:
  /// **'Inglés'**
  String get english;

  /// No description provided for @yourAccount.
  ///
  /// In es, this message translates to:
  /// **'Tu cuenta'**
  String get yourAccount;

  /// No description provided for @mobileNumber.
  ///
  /// In es, this message translates to:
  /// **'Número de celular'**
  String get mobileNumber;

  /// No description provided for @manageContacts.
  ///
  /// In es, this message translates to:
  /// **'Administrar contactos'**
  String get manageContacts;

  /// No description provided for @contactsDescription.
  ///
  /// In es, this message translates to:
  /// **'Encuentra personas que ya usan Vaquita. Tus contactos solo se comparan cuando lo eliges.'**
  String get contactsDescription;

  /// No description provided for @aboutSimulatedProvider.
  ///
  /// In es, this message translates to:
  /// **'Esta versión demuestra el futuro flujo de cobro CoDi con un proveedor simulado.'**
  String get aboutSimulatedProvider;

  /// No description provided for @removeContact.
  ///
  /// In es, this message translates to:
  /// **'¿Eliminar contacto?'**
  String get removeContact;

  /// No description provided for @removeContactDescription.
  ///
  /// In es, this message translates to:
  /// **'No se eliminará de los grupos existentes.'**
  String get removeContactDescription;

  /// No description provided for @couldNotSaveContact.
  ///
  /// In es, this message translates to:
  /// **'No se pudo guardar el contacto.'**
  String get couldNotSaveContact;

  /// No description provided for @couldNotImportContacts.
  ///
  /// In es, this message translates to:
  /// **'No se pudieron importar los contactos.'**
  String get couldNotImportContacts;

  /// No description provided for @contactsPermissionDenied.
  ///
  /// In es, this message translates to:
  /// **'Se denegó el permiso para contactos.'**
  String get contactsPermissionDenied;

  /// No description provided for @importContacts.
  ///
  /// In es, this message translates to:
  /// **'Importar contactos'**
  String get importContacts;

  /// No description provided for @importFromPhone.
  ///
  /// In es, this message translates to:
  /// **'Importar desde el teléfono'**
  String get importFromPhone;

  /// No description provided for @importSelected.
  ///
  /// In es, this message translates to:
  /// **'Importar {count} seleccionados'**
  String importSelected(int count);

  /// No description provided for @removeContactTooltip.
  ///
  /// In es, this message translates to:
  /// **'Eliminar contacto'**
  String get removeContactTooltip;

  /// No description provided for @accountName.
  ///
  /// In es, this message translates to:
  /// **'Nombre'**
  String get accountName;

  /// No description provided for @mexicanMobileNumber.
  ///
  /// In es, this message translates to:
  /// **'Número de celular mexicano'**
  String get mexicanMobileNumber;

  /// No description provided for @cannotReachServer.
  ///
  /// In es, this message translates to:
  /// **'No se puede conectar al servidor de Vaquita.'**
  String get cannotReachServer;

  /// No description provided for @monthlySalary.
  ///
  /// In es, this message translates to:
  /// **'Salario mensual (opcional para divisiones proporcionales)'**
  String get monthlySalary;

  /// No description provided for @alreadyHaveAccount.
  ///
  /// In es, this message translates to:
  /// **'¿Ya tienes una cuenta? Inicia sesión'**
  String get alreadyHaveAccount;

  /// No description provided for @newHere.
  ///
  /// In es, this message translates to:
  /// **'¿Eres nuevo? Crea una cuenta'**
  String get newHere;

  /// No description provided for @acrossAllGroups.
  ///
  /// In es, this message translates to:
  /// **'En todos los grupos'**
  String get acrossAllGroups;

  /// No description provided for @yourGroups.
  ///
  /// In es, this message translates to:
  /// **'Tus grupos'**
  String get yourGroups;

  /// No description provided for @activeGroups.
  ///
  /// In es, this message translates to:
  /// **'{count} activos'**
  String activeGroups(int count);

  /// No description provided for @groupSummary.
  ///
  /// In es, this message translates to:
  /// **'{members} miembros · {expenses} gastos'**
  String groupSummary(int members, int expenses);

  /// No description provided for @groupBalanceOwed.
  ///
  /// In es, this message translates to:
  /// **'te deben'**
  String get groupBalanceOwed;

  /// No description provided for @groupBalanceYouOwe.
  ///
  /// In es, this message translates to:
  /// **'debes'**
  String get groupBalanceYouOwe;

  /// No description provided for @groupBalanceSettled.
  ///
  /// In es, this message translates to:
  /// **'saldado'**
  String get groupBalanceSettled;

  /// No description provided for @groupBalanceSummary.
  ///
  /// In es, this message translates to:
  /// **'Grupo: {summary}'**
  String groupBalanceSummary(String summary);

  /// No description provided for @withYouBalanceSummary.
  ///
  /// In es, this message translates to:
  /// **'Contigo: {summary}'**
  String withYouBalanceSummary(String summary);

  /// No description provided for @noGroupsDescription.
  ///
  /// In es, this message translates to:
  /// **'Crea un grupo y selecciona contactos para comenzar.'**
  String get noGroupsDescription;

  /// No description provided for @inboxEmptyTitle.
  ///
  /// In es, this message translates to:
  /// **'Estás al día'**
  String get inboxEmptyTitle;

  /// No description provided for @inboxEmptyDescription.
  ///
  /// In es, this message translates to:
  /// **'Las invitaciones y los saldos de contactos aparecerán aquí.'**
  String get inboxEmptyDescription;

  /// No description provided for @movementsEmptyDescription.
  ///
  /// In es, this message translates to:
  /// **'Los gastos y liquidaciones de tus grupos aparecerán aquí.'**
  String get movementsEmptyDescription;

  /// No description provided for @invitationDetails.
  ///
  /// In es, this message translates to:
  /// **'Detalles de la invitación'**
  String get invitationDetails;

  /// No description provided for @sharedGroupInvitation.
  ///
  /// In es, this message translates to:
  /// **'Invitación a grupo compartido'**
  String get sharedGroupInvitation;

  /// No description provided for @responseRequired.
  ///
  /// In es, this message translates to:
  /// **'Respuesta requerida'**
  String get responseRequired;

  /// No description provided for @balanceDetails.
  ///
  /// In es, this message translates to:
  /// **'Detalles del saldo'**
  String get balanceDetails;

  /// No description provided for @byGroup.
  ///
  /// In es, this message translates to:
  /// **'Por grupo'**
  String get byGroup;

  /// No description provided for @concepts.
  ///
  /// In es, this message translates to:
  /// **'Conceptos'**
  String get concepts;

  /// No description provided for @noActiveBalances.
  ///
  /// In es, this message translates to:
  /// **'No hay saldos activos de grupos para mostrar.'**
  String get noActiveBalances;

  /// No description provided for @joinGroup.
  ///
  /// In es, this message translates to:
  /// **'¿Unirse a {group}?'**
  String joinGroup(String group);

  /// No description provided for @joinedGroup.
  ///
  /// In es, this message translates to:
  /// **'Te uniste a {group}.'**
  String joinedGroup(String group);

  /// No description provided for @invitationDeclined.
  ///
  /// In es, this message translates to:
  /// **'Rechazaste la invitación a {group}.'**
  String invitationDeclined(String group);

  /// No description provided for @acceptInvitation.
  ///
  /// In es, this message translates to:
  /// **'Aceptar invitación'**
  String get acceptInvitation;

  /// No description provided for @youOweContact.
  ///
  /// In es, this message translates to:
  /// **'Le debes a este contacto'**
  String get youOweContact;

  /// No description provided for @contactOwesYou.
  ///
  /// In es, this message translates to:
  /// **'Este contacto te debe'**
  String get contactOwesYou;

  /// No description provided for @returnToInbox.
  ///
  /// In es, this message translates to:
  /// **'Vuelve a la bandeja para aceptar o rechazar esta invitación.'**
  String get returnToInbox;

  /// No description provided for @memberOwesYou.
  ///
  /// In es, this message translates to:
  /// **'{name} te debe'**
  String memberOwesYou(String name);

  /// No description provided for @youOweMember.
  ///
  /// In es, this message translates to:
  /// **'Le debes a {name}'**
  String youOweMember(String name);

  /// No description provided for @requestPayment.
  ///
  /// In es, this message translates to:
  /// **'Solicitar pago'**
  String get requestPayment;

  /// No description provided for @payContact.
  ///
  /// In es, this message translates to:
  /// **'Pagar a {name}'**
  String payContact(String name);

  /// No description provided for @genericMember.
  ///
  /// In es, this message translates to:
  /// **'Un miembro'**
  String get genericMember;

  /// No description provided for @memberPaid.
  ///
  /// In es, this message translates to:
  /// **'{name} pagó'**
  String memberPaid(String name);

  /// No description provided for @memberPaidMember.
  ///
  /// In es, this message translates to:
  /// **'{from} pagó a {to}'**
  String memberPaidMember(String from, String to);

  /// No description provided for @settlement.
  ///
  /// In es, this message translates to:
  /// **'Liquidación'**
  String get settlement;

  /// No description provided for @today.
  ///
  /// In es, this message translates to:
  /// **'Hoy'**
  String get today;

  /// No description provided for @yesterday.
  ///
  /// In es, this message translates to:
  /// **'Ayer'**
  String get yesterday;

  /// No description provided for @daysAgo.
  ///
  /// In es, this message translates to:
  /// **'Hace {count} días'**
  String daysAgo(int count);

  /// No description provided for @groupCreated.
  ///
  /// In es, this message translates to:
  /// **'Se creó {name}.'**
  String groupCreated(String name);

  /// No description provided for @couldNotCreateGroup.
  ///
  /// In es, this message translates to:
  /// **'No se pudo crear el grupo.'**
  String get couldNotCreateGroup;

  /// No description provided for @goodAfternoon.
  ///
  /// In es, this message translates to:
  /// **'Buenas tardes 👋'**
  String get goodAfternoon;

  /// No description provided for @memberNeedsNamePhone.
  ///
  /// In es, this message translates to:
  /// **'Cada miembro necesita un nombre y número mexicano.'**
  String get memberNeedsNamePhone;

  /// No description provided for @addAtLeastOneMember.
  ///
  /// In es, this message translates to:
  /// **'Agrega al menos un miembro.'**
  String get addAtLeastOneMember;

  /// No description provided for @enterNamePhone.
  ///
  /// In es, this message translates to:
  /// **'Ingresa un nombre y número mexicano.'**
  String get enterNamePhone;

  /// No description provided for @createAGroup.
  ///
  /// In es, this message translates to:
  /// **'Crear un grupo'**
  String get createAGroup;

  /// No description provided for @createGroupDescription.
  ///
  /// In es, this message translates to:
  /// **'Te agregamos automáticamente. Añade cada contacto con su número mexicano.'**
  String get createGroupDescription;

  /// No description provided for @groupIcon.
  ///
  /// In es, this message translates to:
  /// **'Ícono del grupo'**
  String get groupIcon;

  /// No description provided for @personal.
  ///
  /// In es, this message translates to:
  /// **'Personal'**
  String get personal;

  /// No description provided for @shared.
  ///
  /// In es, this message translates to:
  /// **'Compartido'**
  String get shared;

  /// No description provided for @allowSalarySplits.
  ///
  /// In es, this message translates to:
  /// **'Permitir divisiones por salario'**
  String get allowSalarySplits;

  /// No description provided for @salaryOptInOnly.
  ///
  /// In es, this message translates to:
  /// **'Solo pueden usarlo los miembros que acepten'**
  String get salaryOptInOnly;

  /// No description provided for @addSavedContacts.
  ///
  /// In es, this message translates to:
  /// **'Agregar contactos guardados'**
  String get addSavedContacts;

  /// No description provided for @memberName.
  ///
  /// In es, this message translates to:
  /// **'Nombre del miembro'**
  String get memberName;

  /// No description provided for @addMember.
  ///
  /// In es, this message translates to:
  /// **'Agregar miembro'**
  String get addMember;

  /// No description provided for @selectParticipant.
  ///
  /// In es, this message translates to:
  /// **'Selecciona al menos un participante.'**
  String get selectParticipant;

  /// No description provided for @addAnExpense.
  ///
  /// In es, this message translates to:
  /// **'Agregar un gasto'**
  String get addAnExpense;

  /// No description provided for @dinnerExample.
  ///
  /// In es, this message translates to:
  /// **'Cena'**
  String get dinnerExample;

  /// No description provided for @addDescription.
  ///
  /// In es, this message translates to:
  /// **'Agrega una descripción'**
  String get addDescription;

  /// No description provided for @amountGreaterZero.
  ///
  /// In es, this message translates to:
  /// **'Ingresa un monto mayor que cero'**
  String get amountGreaterZero;

  /// No description provided for @paidBy.
  ///
  /// In es, this message translates to:
  /// **'Pagado por'**
  String get paidBy;

  /// No description provided for @equal.
  ///
  /// In es, this message translates to:
  /// **'Igual'**
  String get equal;

  /// No description provided for @bySalary.
  ///
  /// In es, this message translates to:
  /// **'Por salario'**
  String get bySalary;

  /// No description provided for @exactAmount.
  ///
  /// In es, this message translates to:
  /// **'Monto exacto'**
  String get exactAmount;

  /// No description provided for @exactSplitBetween.
  ///
  /// In es, this message translates to:
  /// **'Ingresa el monto exacto que debe cada persona'**
  String get exactSplitBetween;

  /// No description provided for @owes.
  ///
  /// In es, this message translates to:
  /// **'Debe'**
  String get owes;

  /// No description provided for @consumed.
  ///
  /// In es, this message translates to:
  /// **'Consumió'**
  String get consumed;

  /// No description provided for @exactOverpaymentNeedsTotalChange.
  ///
  /// In es, this message translates to:
  /// **'Los pagos superan este total. Cambia el total o incluye a alguien que no haya pagado de más.'**
  String get exactOverpaymentNeedsTotalChange;

  /// No description provided for @exactAmountRemaining.
  ///
  /// In es, this message translates to:
  /// **'Restante: {amount}'**
  String exactAmountRemaining(String amount);

  /// No description provided for @exactSharesMustMatchTotal.
  ///
  /// In es, this message translates to:
  /// **'Las partes exactas deben sumar el total pagado.'**
  String get exactSharesMustMatchTotal;

  /// No description provided for @salaryEligibleOnly.
  ///
  /// In es, this message translates to:
  /// **'Solo participan quienes compartieron su salario.'**
  String get salaryEligibleOnly;

  /// No description provided for @splitBySalaryBetween.
  ///
  /// In es, this message translates to:
  /// **'Dividir por salario entre'**
  String get splitBySalaryBetween;

  /// No description provided for @splitEquallyBetween.
  ///
  /// In es, this message translates to:
  /// **'Dividir en partes iguales entre'**
  String get splitEquallyBetween;

  /// No description provided for @saveExpense.
  ///
  /// In es, this message translates to:
  /// **'Guardar gasto'**
  String get saveExpense;

  /// No description provided for @beachWeekend.
  ///
  /// In es, this message translates to:
  /// **'Fin de semana en la playa'**
  String get beachWeekend;

  /// No description provided for @enterGroupName.
  ///
  /// In es, this message translates to:
  /// **'Ingresa un nombre de grupo'**
  String get enterGroupName;

  /// No description provided for @expenseAdded.
  ///
  /// In es, this message translates to:
  /// **'Se agregó {description}.'**
  String expenseAdded(String description);

  /// No description provided for @couldNotAddExpense.
  ///
  /// In es, this message translates to:
  /// **'No se pudo agregar el gasto.'**
  String get couldNotAddExpense;

  /// No description provided for @groupOptions.
  ///
  /// In es, this message translates to:
  /// **'Opciones del grupo'**
  String get groupOptions;

  /// No description provided for @balances.
  ///
  /// In es, this message translates to:
  /// **'Saldos'**
  String get balances;

  /// No description provided for @expenses.
  ///
  /// In es, this message translates to:
  /// **'Gastos'**
  String get expenses;

  /// No description provided for @membersCount.
  ///
  /// In es, this message translates to:
  /// **'{count} miembros'**
  String membersCount(int count);

  /// No description provided for @sharedGroup.
  ///
  /// In es, this message translates to:
  /// **'Grupo compartido'**
  String get sharedGroup;

  /// No description provided for @personalGroup.
  ///
  /// In es, this message translates to:
  /// **'Grupo personal'**
  String get personalGroup;

  /// No description provided for @editGroupContacts.
  ///
  /// In es, this message translates to:
  /// **'Editar grupo y agregar contactos'**
  String get editGroupContacts;

  /// No description provided for @saveGroup.
  ///
  /// In es, this message translates to:
  /// **'Guardar grupo'**
  String get saveGroup;

  /// No description provided for @enableSalarySplits.
  ///
  /// In es, this message translates to:
  /// **'Activar divisiones por salario'**
  String get enableSalarySplits;

  /// No description provided for @everyMemberConsented.
  ///
  /// In es, this message translates to:
  /// **'Todos los miembros activos dieron su consentimiento.'**
  String get everyMemberConsented;

  /// No description provided for @salarySplitsUnlock.
  ///
  /// In es, this message translates to:
  /// **'Las divisiones se habilitan cuando todos aceptan y dan su consentimiento.'**
  String get salarySplitsUnlock;

  /// No description provided for @contactName.
  ///
  /// In es, this message translates to:
  /// **'Nombre del contacto'**
  String get contactName;

  /// No description provided for @pendingUntilAccept.
  ///
  /// In es, this message translates to:
  /// **'Aparecerá como pendiente hasta que acepte.'**
  String get pendingUntilAccept;

  /// No description provided for @couldNotAddContact.
  ///
  /// In es, this message translates to:
  /// **'No se pudo agregar este contacto.'**
  String get couldNotAddContact;

  /// No description provided for @contactAdded.
  ///
  /// In es, this message translates to:
  /// **'Contacto agregado.'**
  String get contactAdded;

  /// No description provided for @sendInvitation.
  ///
  /// In es, this message translates to:
  /// **'Enviar invitación'**
  String get sendInvitation;

  /// No description provided for @allowGroupSalary.
  ///
  /// In es, this message translates to:
  /// **'Permitir que este grupo use mi salario'**
  String get allowGroupSalary;

  /// No description provided for @salaryPrivacy.
  ///
  /// In es, this message translates to:
  /// **'Tu salario exacto se oculta, pero los resultados proporcionales pueden revelar diferencias salariales relativas.'**
  String get salaryPrivacy;

  /// No description provided for @salaryInferenceDisclosure.
  ///
  /// In es, this message translates to:
  /// **'Aviso de privacidad: los miembros del grupo pueden inferir diferencias salariales relativas a partir de los porcentajes y montos resultantes.'**
  String get salaryInferenceDisclosure;

  /// No description provided for @simulatePayment.
  ///
  /// In es, this message translates to:
  /// **'Simular pago'**
  String get simulatePayment;

  /// No description provided for @noExpensesYet.
  ///
  /// In es, this message translates to:
  /// **'Aún no hay gastos'**
  String get noExpensesYet;

  /// No description provided for @addFirstExpense.
  ///
  /// In es, this message translates to:
  /// **'Agregar el primero'**
  String get addFirstExpense;

  /// No description provided for @invitationSent.
  ///
  /// In es, this message translates to:
  /// **'Invitación enviada a {name}.'**
  String invitationSent(String name);

  /// No description provided for @requestFrom.
  ///
  /// In es, this message translates to:
  /// **'Solicitar a {name}'**
  String requestFrom(String name);

  /// No description provided for @demoPaymentDescription.
  ///
  /// In es, this message translates to:
  /// **'Modo demo: simula una confirmación del proveedor. No se mueve dinero real.'**
  String get demoPaymentDescription;

  /// No description provided for @paymentConfirmed.
  ///
  /// In es, this message translates to:
  /// **'Pago simulado confirmado.'**
  String get paymentConfirmed;

  /// No description provided for @paymentRequestCreated.
  ///
  /// In es, this message translates to:
  /// **'Solicitud de pago creada.'**
  String get paymentRequestCreated;

  /// No description provided for @couldNotConfirmPayment.
  ///
  /// In es, this message translates to:
  /// **'No se pudo confirmar el pago.'**
  String get couldNotConfirmPayment;

  /// No description provided for @salarySplitsEnabled.
  ///
  /// In es, this message translates to:
  /// **'Divisiones por salario activadas'**
  String get salarySplitsEnabled;

  /// No description provided for @salarySplits.
  ///
  /// In es, this message translates to:
  /// **'Divisiones por salario'**
  String get salarySplits;

  /// No description provided for @salaryEnabledDescription.
  ///
  /// In es, this message translates to:
  /// **'Los gastos pueden dividirse proporcionalmente al salario.'**
  String get salaryEnabledDescription;

  /// No description provided for @salaryAvailableDescription.
  ///
  /// In es, this message translates to:
  /// **'Todos aceptaron. Actívalo para nuevos gastos.'**
  String get salaryAvailableDescription;

  /// No description provided for @salaryWaitingDescription.
  ///
  /// In es, this message translates to:
  /// **'Esperando que todos acepten y autoricen el uso del salario.'**
  String get salaryWaitingDescription;

  /// No description provided for @salarySharedGroupRequired.
  ///
  /// In es, this message translates to:
  /// **'Se requiere un grupo compartido para que todos den su consentimiento.'**
  String get salarySharedGroupRequired;

  /// No description provided for @configure.
  ///
  /// In es, this message translates to:
  /// **'Configurar'**
  String get configure;

  /// No description provided for @info.
  ///
  /// In es, this message translates to:
  /// **'Información'**
  String get info;

  /// No description provided for @yourGroupBalance.
  ///
  /// In es, this message translates to:
  /// **'Tu saldo del grupo'**
  String get yourGroupBalance;

  /// No description provided for @youCurrentlyOwe.
  ///
  /// In es, this message translates to:
  /// **'Actualmente debes'**
  String get youCurrentlyOwe;

  /// No description provided for @invitationPending.
  ///
  /// In es, this message translates to:
  /// **'Invitación pendiente'**
  String get invitationPending;

  /// No description provided for @getsBack.
  ///
  /// In es, this message translates to:
  /// **'recibe {amount}'**
  String getsBack(String amount);

  /// No description provided for @owesAmount.
  ///
  /// In es, this message translates to:
  /// **'debe {amount}'**
  String owesAmount(String amount);

  /// No description provided for @request.
  ///
  /// In es, this message translates to:
  /// **'Solicitar'**
  String get request;

  /// No description provided for @pay.
  ///
  /// In es, this message translates to:
  /// **'Pagar'**
  String get pay;

  /// No description provided for @expenseSplitDetails.
  ///
  /// In es, this message translates to:
  /// **'Pagado por {payer} · {mode} entre {count}'**
  String expenseSplitDetails(String payer, String mode, int count);

  /// No description provided for @split.
  ///
  /// In es, this message translates to:
  /// **'dividido'**
  String get split;

  /// No description provided for @serverUnavailable.
  ///
  /// In es, this message translates to:
  /// **'No se puede conectar al servidor de Vaquita. ¿Está Docker en ejecución?'**
  String get serverUnavailable;

  /// No description provided for @serverRequestFailed.
  ///
  /// In es, this message translates to:
  /// **'La solicitud al servidor falló. Revisa Docker e inténtalo de nuevo.'**
  String get serverRequestFailed;

  /// No description provided for @requestFailed.
  ///
  /// In es, this message translates to:
  /// **'La solicitud falló.'**
  String get requestFailed;

  /// No description provided for @movementMetadata.
  ///
  /// In es, this message translates to:
  /// **'{emoji} {group} · {detail} · {date}'**
  String movementMetadata(
      String emoji, String group, String detail, String date);

  /// No description provided for @memberNamesExample.
  ///
  /// In es, this message translates to:
  /// **'Ana, Diego, Sofía'**
  String get memberNamesExample;

  /// No description provided for @expenseDetails.
  ///
  /// In es, this message translates to:
  /// **'Detalles del gasto'**
  String get expenseDetails;

  /// No description provided for @total.
  ///
  /// In es, this message translates to:
  /// **'Total'**
  String get total;

  /// No description provided for @totalPaid.
  ///
  /// In es, this message translates to:
  /// **'Total pagado'**
  String get totalPaid;

  /// No description provided for @consumption.
  ///
  /// In es, this message translates to:
  /// **'Consumo'**
  String get consumption;

  /// No description provided for @overpayment.
  ///
  /// In es, this message translates to:
  /// **'Propina / excedente'**
  String get overpayment;

  /// No description provided for @overpaymentAllocation.
  ///
  /// In es, this message translates to:
  /// **'Distribución de propina / excedente'**
  String get overpaymentAllocation;

  /// No description provided for @finalLiability.
  ///
  /// In es, this message translates to:
  /// **'Responsabilidad final'**
  String get finalLiability;

  /// No description provided for @splitMethod.
  ///
  /// In es, this message translates to:
  /// **'Método de división'**
  String get splitMethod;

  /// No description provided for @equalSplit.
  ///
  /// In es, this message translates to:
  /// **'División igualitaria'**
  String get equalSplit;

  /// No description provided for @exactSplit.
  ///
  /// In es, this message translates to:
  /// **'Consumo exacto'**
  String get exactSplit;

  /// No description provided for @salaryBasedSplit.
  ///
  /// In es, this message translates to:
  /// **'División por salario'**
  String get salaryBasedSplit;

  /// No description provided for @equalSplitExplanation.
  ///
  /// In es, this message translates to:
  /// **'El total se divide en partes iguales. Los centavos restantes se asignan en el orden de los participantes.'**
  String get equalSplitExplanation;

  /// No description provided for @exactSplitExplanation.
  ///
  /// In es, this message translates to:
  /// **'Se ingresa explícitamente el consumo de cada participante. La propina o excedente se asigna proporcionalmente al consumo.'**
  String get exactSplitExplanation;

  /// No description provided for @splitOverpayment.
  ///
  /// In es, this message translates to:
  /// **'Dividir propina / excedente'**
  String get splitOverpayment;

  /// No description provided for @splitOverpaymentDescription.
  ///
  /// In es, this message translates to:
  /// **'Incluye el dinero pagado por encima del total en los saldos de los participantes.'**
  String get splitOverpaymentDescription;

  /// No description provided for @financialStatistics.
  ///
  /// In es, this message translates to:
  /// **'EstadÃ­sticas financieras'**
  String get financialStatistics;

  /// No description provided for @allTime.
  ///
  /// In es, this message translates to:
  /// **'Todo el tiempo'**
  String get allTime;

  /// No description provided for @thisMonth.
  ///
  /// In es, this message translates to:
  /// **'Este mes'**
  String get thisMonth;

  /// No description provided for @distributedOverpayments.
  ///
  /// In es, this message translates to:
  /// **'Propinas / excedentes repartidos'**
  String get distributedOverpayments;

  /// No description provided for @retainedOverpayments.
  ///
  /// In es, this message translates to:
  /// **'Propinas / excedentes retenidos'**
  String get retainedOverpayments;

  /// No description provided for @retainedOverpaymentsDescription.
  ///
  /// In es, this message translates to:
  /// **'El excedente retenido no crea deuda entre participantes.'**
  String get retainedOverpaymentsDescription;

  /// No description provided for @noOverpayments.
  ///
  /// In es, this message translates to:
  /// **'No hay propinas ni excedentes registrados en este periodo.'**
  String get noOverpayments;

  /// No description provided for @salarySplitExplanation.
  ///
  /// In es, this message translates to:
  /// **'El total se distribuye proporcionalmente usando los salarios autorizados. Los valores de salario permanecen privados.'**
  String get salarySplitExplanation;

  /// No description provided for @participantShares.
  ///
  /// In es, this message translates to:
  /// **'Parte de cada participante'**
  String get participantShares;

  /// No description provided for @paidByName.
  ///
  /// In es, this message translates to:
  /// **'Pagado por {name}'**
  String paidByName(String name);

  /// No description provided for @shareOfTotal.
  ///
  /// In es, this message translates to:
  /// **'{percent} del total'**
  String shareOfTotal(String percent);

  /// No description provided for @shareUnavailable.
  ///
  /// In es, this message translates to:
  /// **'Parte no disponible'**
  String get shareUnavailable;

  /// No description provided for @pendingPayments.
  ///
  /// In es, this message translates to:
  /// **'Pagos pendientes'**
  String get pendingPayments;

  /// No description provided for @pendingPaymentsDescription.
  ///
  /// In es, this message translates to:
  /// **'Pagos necesarios para liquidar los saldos del grupo.'**
  String get pendingPaymentsDescription;

  /// No description provided for @noPendingPayments.
  ///
  /// In es, this message translates to:
  /// **'No hay pagos pendientes. Todos están a mano.'**
  String get noPendingPayments;

  /// No description provided for @pendingPaymentFromTo.
  ///
  /// In es, this message translates to:
  /// **'{from} paga a {to}'**
  String pendingPaymentFromTo(String from, String to);

  /// No description provided for @viewPendingPayments.
  ///
  /// In es, this message translates to:
  /// **'Ver pagos pendientes'**
  String get viewPendingPayments;

  /// No description provided for @signOut.
  ///
  /// In es, this message translates to:
  /// **'Cerrar sesión'**
  String get signOut;

  /// No description provided for @signOutDescription.
  ///
  /// In es, this message translates to:
  /// **'Cerrar sesión en este dispositivo'**
  String get signOutDescription;

  /// No description provided for @signOutAll.
  ///
  /// In es, this message translates to:
  /// **'Cerrar todas las sesiones'**
  String get signOutAll;

  /// No description provided for @signOutAllDescription.
  ///
  /// In es, this message translates to:
  /// **'Revocar todas las sesiones de tu cuenta'**
  String get signOutAllDescription;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'es'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
