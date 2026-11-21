import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vaquita_mx/src/models.dart';
import 'package:vaquita_mx/src/expense_allocation.dart';
import 'package:vaquita_mx/l10n/app_localizations.dart';
import 'package:vaquita_mx/src/widgets/salary_inference_notice.dart';
import 'package:vaquita_mx/src/widgets/group_emoji_picker.dart';

part 'sheets/create_group_sheet.dart';
part 'sheets/add_expense_sheet.dart';
part 'sheets/sheet_handle.dart';

class NewGroupInput {
  const NewGroupInput(
      {required this.name,
      required this.memberNames,
      required this.members,
      required this.emoji,
      required this.visibility,
      required this.salarySplitEnabled});

  final String name;
  final List<String> memberNames;
  final List<Map<String, String>> members;
  final String emoji;
  final String visibility;
  final bool salarySplitEnabled;
}

class GroupMemberDraft {
  const GroupMemberDraft({required this.name, this.phone = ''});
  final String name;
  final String phone;
}

class NewExpenseInput {
  const NewExpenseInput({
    required this.description,
    required this.amountCents,
    required this.payerId,
    required this.payers,
    required this.participantIds,
    required this.splitMode,
    this.shares = const [],
    this.percentages = const [],
    this.splitOverpayment = true,
  });

  final String description;
  final int amountCents;
  final String payerId;
  final List<ExpensePayer> payers;
  final List<String> participantIds;
  final String splitMode;
  final List<ExpenseShare> shares;
  final List<ExpensePercentage> percentages;
  final bool splitOverpayment;
}

Future<NewGroupInput?> showCreateGroupSheet(
  BuildContext context, {
  List<AppContact> contacts = const [],
  bool allowShared = false,
}) {
  return showModalBottomSheet<NewGroupInput>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) =>
        _CreateGroupSheet(contacts: contacts, allowShared: allowShared),
  );
}

Future<NewExpenseInput?> showAddExpenseSheet(
  BuildContext context,
  ExpenseGroup group,
) {
  return showModalBottomSheet<NewExpenseInput>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _AddExpenseSheet(group: group),
  );
}
