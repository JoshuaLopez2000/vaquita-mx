// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get appTitle => 'Vaquita MX';

  @override
  String get home => 'Inicio';

  @override
  String get inbox => 'Bandeja';

  @override
  String get movements => 'Movimientos';

  @override
  String get contacts => 'Contactos';

  @override
  String get profile => 'Perfil';

  @override
  String get newGroup => 'Nuevo grupo';

  @override
  String get retry => 'Reintentar';

  @override
  String get cancel => 'Cancelar';

  @override
  String get save => 'Guardar';

  @override
  String get close => 'Cerrar';

  @override
  String get remove => 'Eliminar';

  @override
  String get addContact => 'Agregar contacto';

  @override
  String get noContactsSaved => 'Aún no hay contactos guardados.';

  @override
  String get noGroups => 'Aún no hay grupos';

  @override
  String get noMovements => 'Aún no hay movimientos';

  @override
  String get noExpenses => 'Aún no hay gastos';

  @override
  String get createGroup => 'Crear grupo';

  @override
  String get addExpense => 'Agregar gasto';

  @override
  String get paymentProvider => 'Proveedor de pago';

  @override
  String get simulatedProvider => 'Simulado — no se mueve dinero real';

  @override
  String get signIn => 'Iniciar sesión';

  @override
  String get createAccount => 'Crear cuenta';

  @override
  String get welcomeBack => 'Bienvenido de nuevo';

  @override
  String get createYourAccount => 'Crea tu cuenta';

  @override
  String get email => 'Correo electrónico';

  @override
  String get password => 'Contraseña';

  @override
  String get name => 'Nombre';

  @override
  String get phone => 'Teléfono';

  @override
  String get groupName => 'Nombre del grupo';

  @override
  String get expenseDescription => 'Descripción';

  @override
  String get amount => 'Monto';

  @override
  String get you => 'Tú';

  @override
  String get youOwe => 'Debes';

  @override
  String get youAreOwed => 'Te deben';

  @override
  String get settledUp => 'Saldado';

  @override
  String get accept => 'Aceptar';

  @override
  String get decline => 'Rechazar';

  @override
  String get language => 'Idioma';

  @override
  String get languageDescription => 'Elige el idioma de la aplicación';

  @override
  String get chooseLanguage => 'Elegir idioma';

  @override
  String get spanish => 'Español';

  @override
  String get english => 'Inglés';

  @override
  String get yourAccount => 'Tu cuenta';

  @override
  String get mobileNumber => 'Número de celular';

  @override
  String get manageContacts => 'Administrar contactos';

  @override
  String get contactsDescription =>
      'Encuentra personas que ya usan Vaquita. Tus contactos solo se comparan cuando lo eliges.';

  @override
  String get aboutSimulatedProvider =>
      'Esta versión demuestra el futuro flujo de cobro CoDi con un proveedor simulado.';

  @override
  String get removeContact => '¿Eliminar contacto?';

  @override
  String get removeContactDescription =>
      'No se eliminará de los grupos existentes.';

  @override
  String get couldNotSaveContact => 'No se pudo guardar el contacto.';

  @override
  String get couldNotImportContacts => 'No se pudieron importar los contactos.';

  @override
  String get contactsPermissionDenied => 'Se denegó el permiso para contactos.';

  @override
  String get importContacts => 'Importar contactos';

  @override
  String get importFromPhone => 'Importar desde el teléfono';

  @override
  String importSelected(int count) {
    return 'Importar $count seleccionados';
  }

  @override
  String get removeContactTooltip => 'Eliminar contacto';

  @override
  String get accountName => 'Nombre';

  @override
  String get mexicanMobileNumber => 'Número de celular mexicano';

  @override
  String get cannotReachServer =>
      'No se puede conectar al servidor de Vaquita.';

  @override
  String get monthlySalary =>
      'Salario mensual (opcional para divisiones proporcionales)';

  @override
  String get alreadyHaveAccount => '¿Ya tienes una cuenta? Inicia sesión';

  @override
  String get newHere => '¿Eres nuevo? Crea una cuenta';

  @override
  String get acrossAllGroups => 'En todos los grupos';

  @override
  String get yourGroups => 'Tus grupos';

  @override
  String activeGroups(int count) {
    return '$count activos';
  }

  @override
  String groupSummary(int members, int expenses) {
    return '$members miembros · $expenses gastos';
  }

  @override
  String get groupBalanceOwed => 'te deben';

  @override
  String get groupBalanceYouOwe => 'debes';

  @override
  String get groupBalanceSettled => 'saldado';

  @override
  String groupBalanceSummary(String summary) {
    return 'Grupo: $summary';
  }

  @override
  String withYouBalanceSummary(String summary) {
    return 'Contigo: $summary';
  }

  @override
  String get noGroupsDescription =>
      'Crea un grupo y selecciona contactos para comenzar.';

  @override
  String get inboxEmptyTitle => 'Estás al día';

  @override
  String get inboxEmptyDescription =>
      'Las invitaciones y los saldos de contactos aparecerán aquí.';

  @override
  String get movementsEmptyDescription =>
      'Los gastos y liquidaciones de tus grupos aparecerán aquí.';

  @override
  String get invitationDetails => 'Detalles de la invitación';

  @override
  String get sharedGroupInvitation => 'Invitación a grupo compartido';

  @override
  String get responseRequired => 'Respuesta requerida';

  @override
  String get balanceDetails => 'Detalles del saldo';

  @override
  String get byGroup => 'Por grupo';

  @override
  String get concepts => 'Conceptos';

  @override
  String get noActiveBalances =>
      'No hay saldos activos de grupos para mostrar.';

  @override
  String joinGroup(String group) {
    return '¿Unirse a $group?';
  }

  @override
  String joinedGroup(String group) {
    return 'Te uniste a $group.';
  }

  @override
  String invitationDeclined(String group) {
    return 'Rechazaste la invitación a $group.';
  }

  @override
  String get acceptInvitation => 'Aceptar invitación';

  @override
  String get youOweContact => 'Le debes a este contacto';

  @override
  String get contactOwesYou => 'Este contacto te debe';

  @override
  String get returnToInbox =>
      'Vuelve a la bandeja para aceptar o rechazar esta invitación.';

  @override
  String memberOwesYou(String name) {
    return '$name te debe';
  }

  @override
  String youOweMember(String name) {
    return 'Le debes a $name';
  }

  @override
  String get requestPayment => 'Solicitar pago';

  @override
  String get confirmPaymentReceived => 'Confirmar pago recibido';

  @override
  String get recordPayment => 'Registrar pago';

  @override
  String get waitingForCreditorConfirmation =>
      'La persona acreedora debe confirmar el pago.';

  @override
  String get sharedCreditorSettlementDescription =>
      'En modo demo puedes solicitar el pago; confirmar que lo recibiste solo actualiza el registro y no verifica una transferencia.';

  @override
  String payContact(String name) {
    return 'Pagar a $name';
  }

  @override
  String get genericMember => 'Un miembro';

  @override
  String memberPaid(String name) {
    return '$name pagó';
  }

  @override
  String memberPaidMember(String from, String to) {
    return '$from pagó a $to';
  }

  @override
  String get settlement => 'Liquidación';

  @override
  String get today => 'Hoy';

  @override
  String get yesterday => 'Ayer';

  @override
  String daysAgo(int count) {
    return 'Hace $count días';
  }

  @override
  String groupCreated(String name) {
    return 'Se creó $name.';
  }

  @override
  String get couldNotCreateGroup => 'No se pudo crear el grupo.';

  @override
  String get couldNotUpdateGroup =>
      'No se pudo guardar el grupo. Comprueba tu conexión y que tengas permiso para editarlo.';

  @override
  String get goodAfternoon => 'Buenas tardes 👋';

  @override
  String get memberNeedsNamePhone =>
      'Cada miembro necesita un nombre y número mexicano.';

  @override
  String get addAtLeastOneMember => 'Agrega al menos un miembro.';

  @override
  String get enterNamePhone => 'Ingresa un nombre y número mexicano.';

  @override
  String get createAGroup => 'Crear un grupo';

  @override
  String get createGroupDescription =>
      'Te agregamos automáticamente. Añade cada contacto con su número mexicano.';

  @override
  String get groupIcon => 'Ícono del grupo';

  @override
  String get personal => 'Personal';

  @override
  String get shared => 'Compartido';

  @override
  String get allowSalarySplits => 'Permitir divisiones por salario';

  @override
  String get salaryOptInOnly => 'Solo pueden usarlo los miembros que acepten';

  @override
  String get addSavedContacts => 'Agregar contactos guardados';

  @override
  String get memberName => 'Nombre del miembro';

  @override
  String get addMember => 'Agregar miembro';

  @override
  String get selectParticipant => 'Selecciona al menos un participante.';

  @override
  String get addAnExpense => 'Agregar un gasto';

  @override
  String get dinnerExample => 'Cena';

  @override
  String get addDescription => 'Agrega una descripción';

  @override
  String get amountGreaterZero => 'Ingresa un monto mayor que cero';

  @override
  String get paidBy => 'Pagado por';

  @override
  String get equal => 'Igual';

  @override
  String get bySalary => 'Por salario';

  @override
  String get exactAmount => 'Monto exacto';

  @override
  String get exactSplitBetween =>
      'Ingresa el monto exacto que debe cada persona';

  @override
  String get owes => 'Debe';

  @override
  String get consumed => 'Consumió';

  @override
  String get exactOverpaymentNeedsTotalChange =>
      'Los pagos superan este total. Cambia el total o incluye a alguien que no haya pagado de más.';

  @override
  String exactAmountRemaining(String amount) {
    return 'Restante: $amount';
  }

  @override
  String get exactSharesMustMatchTotal =>
      'Las partes exactas deben sumar el total pagado.';

  @override
  String get salaryEligibleOnly =>
      'Solo participan quienes compartieron su salario.';

  @override
  String get splitBySalaryBetween => 'Dividir por salario entre';

  @override
  String get splitEquallyBetween => 'Dividir en partes iguales entre';

  @override
  String get saveExpense => 'Guardar gasto';

  @override
  String get beachWeekend => 'Fin de semana en la playa';

  @override
  String get enterGroupName => 'Ingresa un nombre de grupo';

  @override
  String expenseAdded(String description) {
    return 'Se agregó $description.';
  }

  @override
  String get couldNotAddExpense => 'No se pudo agregar el gasto.';

  @override
  String get groupOptions => 'Opciones del grupo';

  @override
  String get balances => 'Saldos';

  @override
  String get expenses => 'Gastos';

  @override
  String membersCount(int count) {
    return '$count miembros';
  }

  @override
  String get sharedGroup => 'Grupo compartido';

  @override
  String get personalGroup => 'Grupo personal';

  @override
  String get editGroupContacts => 'Editar grupo y agregar contactos';

  @override
  String get saveGroup => 'Guardar grupo';

  @override
  String get enableSalarySplits => 'Activar divisiones por salario';

  @override
  String get everyMemberConsented =>
      'Todos los miembros activos dieron su consentimiento.';

  @override
  String get salarySplitsUnlock =>
      'Las divisiones se habilitan cuando todos aceptan y dan su consentimiento.';

  @override
  String get contactName => 'Nombre del contacto';

  @override
  String get pendingUntilAccept => 'Aparecerá como pendiente hasta que acepte.';

  @override
  String get couldNotAddContact => 'No se pudo agregar este contacto.';

  @override
  String get contactAdded => 'Contacto agregado.';

  @override
  String get sendInvitation => 'Enviar invitación';

  @override
  String get allowGroupSalary => 'Permitir que este grupo use mi salario';

  @override
  String get salaryPrivacy =>
      'Tu salario exacto se oculta, pero los resultados proporcionales pueden revelar diferencias salariales relativas.';

  @override
  String get salaryInferenceDisclosure =>
      'Aviso de privacidad: los miembros del grupo pueden inferir diferencias salariales relativas a partir de los porcentajes y montos resultantes.';

  @override
  String get simulatePayment => 'Simular pago';

  @override
  String get noExpensesYet => 'Aún no hay gastos';

  @override
  String get addFirstExpense => 'Agregar el primero';

  @override
  String invitationSent(String name) {
    return 'Invitación enviada a $name.';
  }

  @override
  String requestFrom(String name) {
    return 'Solicitar a $name';
  }

  @override
  String confirmReceivedFrom(String name) {
    return 'Confirmar pago recibido de $name';
  }

  @override
  String get demoPaymentDescription =>
      'Modo demo: simula una confirmación del proveedor. No se mueve dinero real.';

  @override
  String get manualSettlementDescription =>
      'Registra el monto acordado. No inicia una transferencia.';

  @override
  String get paymentConfirmed => 'Pago simulado confirmado.';

  @override
  String get paymentReceivedRecorded => 'Pago recibido registrado.';

  @override
  String get settlementRecorded => 'Liquidación registrada.';

  @override
  String get paymentRequestCreated => 'Solicitud de pago creada.';

  @override
  String get couldNotConfirmPayment => 'No se pudo confirmar el pago.';

  @override
  String get settlementAmount => 'Monto a liquidar';

  @override
  String get settleAll => 'Liquidar todo';

  @override
  String get settlementAmountError =>
      'Introduce un monto hasta el saldo pendiente.';

  @override
  String get salarySplitsEnabled => 'Divisiones por salario activadas';

  @override
  String get salarySplits => 'Divisiones por salario';

  @override
  String get salaryEnabledDescription =>
      'Los gastos pueden dividirse proporcionalmente al salario.';

  @override
  String get salaryAvailableDescription =>
      'Todos aceptaron. Actívalo para nuevos gastos.';

  @override
  String get salaryWaitingDescription =>
      'Esperando que todos acepten y autoricen el uso del salario.';

  @override
  String get salarySharedGroupRequired =>
      'Se requiere un grupo compartido para que todos den su consentimiento.';

  @override
  String get configure => 'Configurar';

  @override
  String get info => 'Información';

  @override
  String get yourGroupBalance => 'Tu saldo del grupo';

  @override
  String get youCurrentlyOwe => 'Actualmente debes';

  @override
  String get invitationPending => 'Invitación pendiente';

  @override
  String getsBack(String amount) {
    return 'recibe $amount';
  }

  @override
  String owesAmount(String amount) {
    return 'debe $amount';
  }

  @override
  String get request => 'Solicitar';

  @override
  String get pay => 'Pagar';

  @override
  String expenseSplitDetails(String payer, String mode, int count) {
    return 'Pagado por $payer · $mode entre $count';
  }

  @override
  String get split => 'dividido';

  @override
  String get serverUnavailable =>
      'No se puede conectar al servidor de Vaquita. ¿Está Docker en ejecución?';

  @override
  String get serverRequestFailed =>
      'La solicitud al servidor falló. Revisa Docker e inténtalo de nuevo.';

  @override
  String get requestFailed => 'La solicitud falló.';

  @override
  String movementMetadata(
      String emoji, String group, String detail, String date) {
    return '$emoji $group · $detail · $date';
  }

  @override
  String get memberNamesExample => 'Ana, Diego, Sofía';

  @override
  String get expenseDetails => 'Detalles del gasto';

  @override
  String get total => 'Total';

  @override
  String get totalPaid => 'Total pagado';

  @override
  String get consumption => 'Consumo';

  @override
  String get overpayment => 'Propina / excedente';

  @override
  String get overpaymentAllocation => 'Distribución de propina / excedente';

  @override
  String get finalLiability => 'Responsabilidad final';

  @override
  String get splitMethod => 'Método de división';

  @override
  String get equalSplit => 'División igualitaria';

  @override
  String get exactSplit => 'Consumo exacto';

  @override
  String get salaryBasedSplit => 'División por salario';

  @override
  String get equalSplitExplanation =>
      'El total se divide en partes iguales. Los centavos restantes se asignan en el orden de los participantes.';

  @override
  String get exactSplitExplanation =>
      'Se ingresa explícitamente el consumo de cada participante. La propina o excedente se asigna proporcionalmente al consumo.';

  @override
  String get splitOverpayment => 'Dividir propina / excedente';

  @override
  String get splitOverpaymentDescription =>
      'Incluye el dinero pagado por encima del total en los saldos de los participantes.';

  @override
  String get financialStatistics => 'Estadísticas financieras';

  @override
  String get allTime => 'Todo el tiempo';

  @override
  String get thisMonth => 'Este mes';

  @override
  String get distributedOverpayments => 'Propinas / excedentes repartidos';

  @override
  String get retainedOverpayments => 'Propinas / excedentes retenidos';

  @override
  String get retainedOverpaymentsDescription =>
      'El excedente retenido no crea deuda entre participantes.';

  @override
  String get noOverpayments =>
      'No hay propinas ni excedentes registrados en este periodo.';

  @override
  String get salarySplitExplanation =>
      'El total se distribuye proporcionalmente usando los salarios autorizados. Los valores de salario permanecen privados.';

  @override
  String get participantShares => 'Parte de cada participante';

  @override
  String paidByName(String name) {
    return 'Pagado por $name';
  }

  @override
  String shareOfTotal(String percent) {
    return '$percent del total';
  }

  @override
  String get shareUnavailable => 'Parte no disponible';

  @override
  String get pendingPayments => 'Pagos pendientes';

  @override
  String get pendingPaymentsDescription =>
      'Pagos necesarios para liquidar los saldos del grupo.';

  @override
  String get noPendingPayments =>
      'No hay pagos pendientes. Todos están a mano.';

  @override
  String pendingPaymentFromTo(String from, String to) {
    return '$from paga a $to';
  }

  @override
  String get viewPendingPayments => 'Ver pagos pendientes';

  @override
  String get signOut => 'Cerrar sesión';

  @override
  String get signOutDescription => 'Cerrar sesión en este dispositivo';

  @override
  String get signOutAll => 'Cerrar todas las sesiones';

  @override
  String get signOutAllDescription => 'Revocar todas las sesiones de tu cuenta';

  @override
  String get loginOrSignUp => 'Iniciar sesión / Registrarse';

  @override
  String get loginOrSignUpDescription =>
      'Crea una cuenta para sincronizar tus grupos';

  @override
  String get syncLocalGroupsTitle => '¿Sincronizar tus grupos locales?';

  @override
  String get syncLocalGroupsDescription =>
      'La sincronización envía tus grupos locales y su historial a tu cuenta. Los miembros podrían recibir invitaciones cuando un grupo se comparta.';

  @override
  String get later => 'Más tarde';

  @override
  String get syncNow => 'Sincronizar ahora';

  @override
  String get syncLocalGroupsButton => 'Sincronizar grupos locales';

  @override
  String get syncCompleted => 'Grupos locales sincronizados';

  @override
  String get syncFailed =>
      'No se pudo sincronizar. Tus datos locales están seguros; inténtalo de nuevo.';

  @override
  String get groupStoredLocally => 'Local';

  @override
  String get groupStoredOnServer => 'Servidor';

  @override
  String get savedOfflineWillSync =>
      'Guardado sin conexión. Se sincronizará al volver internet.';

  @override
  String pendingSyncCount(int count) {
    return '$count pendiente(s)';
  }

  @override
  String pendingSyncBannerTitle(int count) {
    return '$count cambios sin conexión pendientes de sincronizar';
  }

  @override
  String get pendingSyncBannerDescription =>
      'Guardados en este dispositivo. Se sincronizarán automáticamente al volver tu conexión.';

  @override
  String failedSyncBannerTitle(int count) {
    return '$count cambios sin conexión no pudieron sincronizarse';
  }

  @override
  String get discard => 'Descartar';

  @override
  String get paymentRequestsRequireInternet =>
      'Las solicitudes de pago requieren conexión a internet.';

  @override
  String get byPercentage => 'Porcentaje';

  @override
  String get percentageSplit => 'División por porcentaje';

  @override
  String get percentageSplitBetween => 'Ingresa el porcentaje de cada persona';

  @override
  String get percentageSplitExplanation =>
      'Cada porcentaje usa precisión fija de dos decimales y suma 100.00%. Los centavos restantes se asignan al mayor residuo y, en empate, según el orden de participantes.';

  @override
  String percentageRemaining(String percentage) {
    return 'Restante: $percentage%';
  }

  @override
  String get percentagesMustTotalHundred =>
      'Los porcentajes deben ser mayores a 0% y sumar exactamente 100.00%.';

  @override
  String get reversed => 'Revertido';

  @override
  String get replacement => 'Reemplazo';

  @override
  String get settlementsHistory => 'Liquidaciones';

  @override
  String get settlementDetails => 'Detalle de liquidación';

  @override
  String get reverseExpense => 'Revertir gasto';

  @override
  String get reverseAndReplaceExpense => 'Revertir y reemplazar';

  @override
  String get reverseSettlement => 'Revertir liquidación';

  @override
  String get reverseAndReplaceSettlement => 'Revertir y registrar reemplazo';

  @override
  String get reversalReasonLabel => 'Motivo de la reversión';

  @override
  String get reversalReasonHint => 'Ej. Monto incorrecto o registro duplicado';

  @override
  String get reversalReasonRequired =>
      'Ingresa un motivo (máx. 500 caracteres).';

  @override
  String get confirmReversal => 'Confirmar reversión';

  @override
  String get reversalAuditTitle => 'Registro revertido';

  @override
  String reversedByName(String name) {
    return 'Revertido por $name';
  }

  @override
  String reversalReasonValue(String reason) {
    return 'Motivo: $reason';
  }

  @override
  String get replacesOriginalRecord =>
      'Reemplaza un registro revertido anterior.';

  @override
  String get replacedByRecord =>
      'Reemplazado por un registro nuevo en el historial.';

  @override
  String get expenseReversed => 'Gasto revertido';

  @override
  String get settlementReversed => 'Liquidación revertida';

  @override
  String get couldNotReverseRecord => 'No se pudo revertir el registro.';

  @override
  String get syncBeforeReversal =>
      'Sincroniza este registro pendiente antes de revertirlo.';

  @override
  String expenseReversalMovement(String description) {
    return 'Reversión de gasto: $description';
  }

  @override
  String get settlementReversalMovement => 'Reversión de liquidación';

  @override
  String get compensatingEntry => 'Asiento compensatorio';
}
