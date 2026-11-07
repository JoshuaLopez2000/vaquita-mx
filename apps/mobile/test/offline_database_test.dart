import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vaquita_mx/src/api_client.dart';
import 'package:vaquita_mx/src/models.dart';
import 'package:vaquita_mx/src/offline_database.dart';
import 'package:vaquita_mx/src/store.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('persists group history and keeps per-account sync consent', () async {
    final directory = await Directory.systemTemp.createTemp('vaquita-offline-');
    final path = p.join(directory.path, 'test.db');
    var database = await OfflineDatabase.open(databasePath: path);
    final group = ExpenseGroup(
      id: 'local_group_1',
      name: 'Dinner',
      emoji: '🍲',
      members: const [
        Member(id: 'me', name: 'Ana'),
        Member(id: 'local_member_1', name: 'Beto'),
      ],
      expenses: [
        Expense(
          id: 'local_expense_1',
          description: 'Soup',
          amountCents: 101,
          payerId: 'me',
          payers: const [ExpensePayer(memberId: 'me', amountCents: 101)],
          participantIds: const ['me', 'local_member_1'],
          splitMode: 'exact',
          shares: const {'me': 50, 'local_member_1': 51},
          splitOverpayment: false,
          createdAt: DateTime.utc(2026, 11, 7),
        ),
      ],
      settlements: [
        Settlement(
          id: 'local_settlement_1',
          fromMemberId: 'local_member_1',
          toMemberId: 'me',
          amountCents: 20,
          createdAt: DateTime.utc(2026, 11, 8),
        ),
      ],
    );

    await database.saveGroup(group);
    expect(await database.isPending(group.id), isTrue);
    expect(await database.revision(group.id), 1);
    expect(await database.syncEnabled('account-1'), isFalse);
    await database.setSyncEnabled('account-1', true);
    expect(await database.syncEnabled('account-1'), isTrue);
    await database.close();

    database = await OfflineDatabase.open(databasePath: path);
    final restored = (await database.loadGroups()).single;
    expect(restored.id, group.id);
    expect(restored.expenses.single.amountCents, 101);
    expect(restored.expenses.single.shares, {'me': 50, 'local_member_1': 51});
    expect(restored.settlements.single.amountCents, 20);
    expect(await database.syncEnabled('account-1'), isTrue);
    expect(await database.syncEnabled('account-2'), isFalse);

    await database.markSynced(group.id, 'remote-group-1', 1);
    expect(await database.isPending(group.id), isFalse);
    await database.saveGroup(
      ExpenseGroup(
        id: group.id,
        name: 'Dinner edited offline',
        emoji: group.emoji,
        members: group.members,
        expenses: group.expenses,
        settlements: group.settlements,
      ),
    );
    expect(await database.isPending(group.id), isTrue);
    expect(await database.revision(group.id), 2);

    await database.close();
    await directory.delete(recursive: true);
  });

  test('creates and allocates an expense locally without an account', () async {
    final store = DemoStore.offline(
      ApiClient(baseUrl: 'http://example.test'),
      null,
    );
    await store.createGroup(
      name: 'Dinner',
      emoji: '🍲',
      memberNames: const ['Beto'],
    );
    final group = store.groups.single;
    final guest = group.members[1];

    await store.addExpense(
      groupId: group.id,
      description: 'Soup',
      amountCents: 101,
      payerId: 'me',
      payers: const [ExpensePayer(memberId: 'me', amountCents: 101)],
      participantIds: ['me', guest.id],
      splitMode: 'exact',
      shares: [
        const ExpenseShare(memberId: 'me', amountCents: 50),
        ExpenseShare(memberId: guest.id, amountCents: 51),
      ],
      splitOverpayment: false,
    );

    expect(store.currentUserBalance(group), 51);
    expect(store.balanceWith(group, guest), 51);
    store.dispose();
  });
}
