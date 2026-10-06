// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Vaquita MX';

  @override
  String get home => 'Home';

  @override
  String get inbox => 'Inbox';

  @override
  String get movements => 'Movements';

  @override
  String get contacts => 'Contacts';

  @override
  String get profile => 'Profile';

  @override
  String get newGroup => 'New group';

  @override
  String get retry => 'Retry';

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String get close => 'Close';

  @override
  String get remove => 'Remove';

  @override
  String get addContact => 'Add contact';

  @override
  String get noContactsSaved => 'No contacts saved yet.';

  @override
  String get noGroups => 'No groups yet';

  @override
  String get noMovements => 'No movements yet';

  @override
  String get noExpenses => 'No expenses yet';

  @override
  String get createGroup => 'Create group';

  @override
  String get addExpense => 'Add expense';

  @override
  String get paymentProvider => 'Payment provider';

  @override
  String get simulatedProvider => 'Simulated — no real money moves';

  @override
  String get signIn => 'Sign in';

  @override
  String get createAccount => 'Create account';

  @override
  String get welcomeBack => 'Welcome back';

  @override
  String get createYourAccount => 'Create your account';

  @override
  String get email => 'Email';

  @override
  String get password => 'Password';

  @override
  String get name => 'Name';

  @override
  String get phone => 'Phone';

  @override
  String get groupName => 'Group name';

  @override
  String get expenseDescription => 'Description';

  @override
  String get amount => 'Amount';

  @override
  String get you => 'You';

  @override
  String get youOwe => 'You owe';

  @override
  String get youAreOwed => 'You are owed';

  @override
  String get settledUp => 'Settled up';

  @override
  String get accept => 'Accept';

  @override
  String get decline => 'Decline';

  @override
  String get language => 'Language';

  @override
  String get languageDescription => 'Choose the app language';

  @override
  String get chooseLanguage => 'Choose language';

  @override
  String get spanish => 'Spanish';

  @override
  String get english => 'English';

  @override
  String get yourAccount => 'Your account';

  @override
  String get mobileNumber => 'Mobile number';

  @override
  String get manageContacts => 'Manage contacts';

  @override
  String get contactsDescription =>
      'Find people already using Vaquita. Your contacts are matched only after you choose this.';

  @override
  String get aboutSimulatedProvider =>
      'This build demonstrates the future CoDi collection flow with a simulated provider.';

  @override
  String get removeContact => 'Remove contact?';

  @override
  String get removeContactDescription =>
      'This will not remove them from any existing groups.';

  @override
  String get couldNotSaveContact => 'Could not save contact.';

  @override
  String get couldNotImportContacts => 'Could not import contacts.';

  @override
  String get contactsPermissionDenied => 'Contacts permission was denied.';

  @override
  String get importContacts => 'Import contacts';

  @override
  String get importFromPhone => 'Import from phone';

  @override
  String importSelected(int count) {
    return 'Import $count selected';
  }

  @override
  String get removeContactTooltip => 'Remove contact';

  @override
  String get accountName => 'Name';

  @override
  String get mexicanMobileNumber => 'Mexican mobile number';

  @override
  String get cannotReachServer => 'Cannot reach the Vaquita server.';

  @override
  String get monthlySalary =>
      'Monthly salary (optional for proportional splits)';

  @override
  String get alreadyHaveAccount => 'Already have an account? Sign in';

  @override
  String get newHere => 'New here? Create an account';

  @override
  String get acrossAllGroups => 'Across all groups';

  @override
  String get yourGroups => 'Your groups';

  @override
  String activeGroups(int count) {
    return '$count active';
  }

  @override
  String groupSummary(int members, int expenses) {
    return '$members members · $expenses expenses';
  }

  @override
  String get groupBalanceOwed => 'you are owed';

  @override
  String get groupBalanceYouOwe => 'you owe';

  @override
  String get groupBalanceSettled => 'settled up';

  @override
  String groupBalanceSummary(String summary) {
    return 'Group: $summary';
  }

  @override
  String withYouBalanceSummary(String summary) {
    return 'With you: $summary';
  }

  @override
  String get noGroupsDescription =>
      'Create a group and select contacts to get started.';

  @override
  String get inboxEmptyTitle => 'You\'re all caught up';

  @override
  String get inboxEmptyDescription =>
      'Invitations and contact balances will appear here.';

  @override
  String get movementsEmptyDescription =>
      'Expenses and settlements from your groups will appear here.';

  @override
  String get invitationDetails => 'Invitation details';

  @override
  String get sharedGroupInvitation => 'Shared group invitation';

  @override
  String get responseRequired => 'Response required';

  @override
  String get balanceDetails => 'Balance details';

  @override
  String get byGroup => 'By group';

  @override
  String get concepts => 'Concepts';

  @override
  String get noActiveBalances => 'No active group balances to show.';

  @override
  String joinGroup(String group) {
    return 'Join $group?';
  }

  @override
  String joinedGroup(String group) {
    return 'You joined $group.';
  }

  @override
  String invitationDeclined(String group) {
    return 'Invitation to $group declined.';
  }

  @override
  String get acceptInvitation => 'Accept invitation';

  @override
  String get youOweContact => 'You owe this contact';

  @override
  String get contactOwesYou => 'This contact owes you';

  @override
  String get returnToInbox =>
      'Return to Inbox to accept or decline this invitation.';

  @override
  String memberOwesYou(String name) {
    return '$name owes you';
  }

  @override
  String youOweMember(String name) {
    return 'You owe $name';
  }

  @override
  String get requestPayment => 'Request payment';

  @override
  String payContact(String name) {
    return 'Pay $name';
  }

  @override
  String get genericMember => 'A member';

  @override
  String memberPaid(String name) {
    return '$name paid';
  }

  @override
  String memberPaidMember(String from, String to) {
    return '$from paid $to';
  }

  @override
  String get settlement => 'Settlement';

  @override
  String get today => 'Today';

  @override
  String get yesterday => 'Yesterday';

  @override
  String daysAgo(int count) {
    return '$count days ago';
  }

  @override
  String groupCreated(String name) {
    return '$name created.';
  }

  @override
  String get couldNotCreateGroup => 'Could not create the group.';

  @override
  String get goodAfternoon => 'Good afternoon 👋';

  @override
  String get memberNeedsNamePhone =>
      'Each member needs a name and Mexican phone number.';

  @override
  String get addAtLeastOneMember => 'Add at least one member.';

  @override
  String get enterNamePhone => 'Enter a name and Mexican phone number.';

  @override
  String get createAGroup => 'Create a group';

  @override
  String get createGroupDescription =>
      'You are added automatically. Add each contact with their Mexican phone number.';

  @override
  String get groupIcon => 'Group icon';

  @override
  String get personal => 'Personal';

  @override
  String get shared => 'Shared';

  @override
  String get allowSalarySplits => 'Allow salary-based splits';

  @override
  String get salaryOptInOnly => 'Only members who opt in can use this';

  @override
  String get addSavedContacts => 'Add saved contacts';

  @override
  String get memberName => 'Member name';

  @override
  String get addMember => 'Add member';

  @override
  String get selectParticipant => 'Select at least one participant.';

  @override
  String get addAnExpense => 'Add an expense';

  @override
  String get dinnerExample => 'Dinner';

  @override
  String get addDescription => 'Add a description';

  @override
  String get amountGreaterZero => 'Enter an amount greater than zero';

  @override
  String get paidBy => 'Paid by';

  @override
  String get equal => 'Equal';

  @override
  String get bySalary => 'By salary';

  @override
  String get exactAmount => 'Exact amount';

  @override
  String get exactSplitBetween => 'Enter the exact amount each person owes';

  @override
  String get owes => 'Owes';

  @override
  String get consumed => 'Consumed';

  @override
  String get exactOverpaymentNeedsTotalChange =>
      'The payments exceed this total. Change the total or include someone who did not overpay.';

  @override
  String exactAmountRemaining(String amount) {
    return 'Remaining: $amount';
  }

  @override
  String get exactSharesMustMatchTotal =>
      'The exact shares must add up to the total paid.';

  @override
  String get salaryEligibleOnly =>
      'Only members who shared their salary are eligible.';

  @override
  String get splitBySalaryBetween => 'Split by salary between';

  @override
  String get splitEquallyBetween => 'Split equally between';

  @override
  String get saveExpense => 'Save expense';

  @override
  String get beachWeekend => 'Beach weekend';

  @override
  String get enterGroupName => 'Enter a group name';

  @override
  String expenseAdded(String description) {
    return '$description added.';
  }

  @override
  String get couldNotAddExpense => 'Could not add the expense.';

  @override
  String get groupOptions => 'Group options';

  @override
  String get balances => 'Balances';

  @override
  String get expenses => 'Expenses';

  @override
  String membersCount(int count) {
    return '$count members';
  }

  @override
  String get sharedGroup => 'Shared group';

  @override
  String get personalGroup => 'Personal group';

  @override
  String get editGroupContacts => 'Edit group and add contacts';

  @override
  String get saveGroup => 'Save group';

  @override
  String get enableSalarySplits => 'Enable salary-based splits';

  @override
  String get everyMemberConsented => 'Every active member has consented.';

  @override
  String get salarySplitsUnlock =>
      'Salary splits unlock after every member accepts and opts in.';

  @override
  String get contactName => 'Contact name';

  @override
  String get pendingUntilAccept =>
      'They will appear as pending until they accept.';

  @override
  String get couldNotAddContact => 'Could not add this contact.';

  @override
  String get contactAdded => 'Contact added.';

  @override
  String get sendInvitation => 'Send invitation';

  @override
  String get allowGroupSalary => 'Allow this group to use my salary';

  @override
  String get salaryPrivacy =>
      'Your exact salary is hidden, but proportional results can reveal relative salary differences.';

  @override
  String get salaryInferenceDisclosure =>
      'Privacy notice: group members may infer relative salary differences from the resulting percentages and payment amounts.';

  @override
  String get simulatePayment => 'Simulate payment';

  @override
  String get noExpensesYet => 'No expenses yet';

  @override
  String get addFirstExpense => 'Add the first one';

  @override
  String invitationSent(String name) {
    return 'Invitation sent to $name.';
  }

  @override
  String requestFrom(String name) {
    return 'Request from $name';
  }

  @override
  String get demoPaymentDescription =>
      'Demo mode: this simulates a confirmed provider callback. No real money moves.';

  @override
  String get paymentConfirmed => 'Simulated payment confirmed.';

  @override
  String get paymentRequestCreated => 'Payment request created.';

  @override
  String get couldNotConfirmPayment => 'Could not confirm the payment.';

  @override
  String get salarySplitsEnabled => 'Salary-based splits enabled';

  @override
  String get salarySplits => 'Salary-based splits';

  @override
  String get salaryEnabledDescription =>
      'Expenses can be divided in proportion to salary.';

  @override
  String get salaryAvailableDescription =>
      'Everyone consented. Turn it on to use it for new expenses.';

  @override
  String get salaryWaitingDescription =>
      'Waiting for every member to accept and share salary consent.';

  @override
  String get salarySharedGroupRequired =>
      'Salary splits require a shared group so every member can consent.';

  @override
  String get configure => 'Configure';

  @override
  String get info => 'Info';

  @override
  String get yourGroupBalance => 'Your group balance';

  @override
  String get youCurrentlyOwe => 'You currently owe';

  @override
  String get invitationPending => 'Invitation pending';

  @override
  String getsBack(String amount) {
    return 'gets back $amount';
  }

  @override
  String owesAmount(String amount) {
    return 'owes $amount';
  }

  @override
  String get request => 'Request';

  @override
  String get pay => 'Pay';

  @override
  String expenseSplitDetails(String payer, String mode, int count) {
    return 'Paid by $payer · $mode $count ways';
  }

  @override
  String get split => 'split';

  @override
  String get serverUnavailable =>
      'Cannot reach the Vaquita server. Is Docker running?';

  @override
  String get serverRequestFailed =>
      'The server request failed. Check Docker and try again.';

  @override
  String get requestFailed => 'Request failed.';

  @override
  String movementMetadata(
      String emoji, String group, String detail, String date) {
    return '$emoji $group · $detail · $date';
  }

  @override
  String get memberNamesExample => 'Ana, Diego, Sofía';

  @override
  String get expenseDetails => 'Expense details';

  @override
  String get total => 'Total';

  @override
  String get splitMethod => 'Split method';

  @override
  String get equalSplit => 'Equal split';

  @override
  String get salaryBasedSplit => 'Salary-based split';

  @override
  String get equalSplitExplanation =>
      'The total is divided equally. Remaining cents are assigned in participant order.';

  @override
  String get salarySplitExplanation =>
      'The total is distributed proportionally using opted-in salaries. Salary values remain private.';

  @override
  String get participantShares => 'Participant shares';

  @override
  String paidByName(String name) {
    return 'Paid by $name';
  }

  @override
  String shareOfTotal(String percent) {
    return '$percent of total';
  }

  @override
  String get shareUnavailable => 'Share unavailable';

  @override
  String get pendingPayments => 'Pending payments';

  @override
  String get pendingPaymentsDescription =>
      'Payments needed to settle the group balances.';

  @override
  String get noPendingPayments =>
      'There are no pending payments. Everyone is settled up.';

  @override
  String pendingPaymentFromTo(String from, String to) {
    return '$from pays $to';
  }

  @override
  String get viewPendingPayments => 'View pending payments';

  @override
  String get signOut => 'Sign out';

  @override
  String get signOutDescription => 'Sign out on this device';

  @override
  String get signOutAll => 'Sign out everywhere';

  @override
  String get signOutAllDescription => 'Revoke every session for your account';
}
