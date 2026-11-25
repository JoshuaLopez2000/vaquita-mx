import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaquita_mx/src/app.dart';
import 'package:vaquita_mx/src/store.dart';
import 'package:vaquita_mx/src/theme/vaquita_theme.dart';
import 'package:vaquita_mx/src/widgets/vaquita_brand.dart';

void main() {
  testWidgets(
      'displays branded bootstrap screen during startup and transitions to offline home',
      (tester) async {
    final completer = Completer<DemoStore>();

    await tester.pumpWidget(
      VaquitaApp(initializeStore: () => completer.future),
    );
    await tester.pump();

    expect(find.byType(VaquitaBootstrapScreen), findsOneWidget);
    expect(find.byType(VaquitaLogoMark), findsOneWidget);
    expect(find.text('VAQUITA MX'), findsOneWidget);
    expect(find.text('Preparando tus grupos y saldos…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    final seeded = DemoStore.seeded();
    completer.complete(seeded);
    await tester.pumpAndSettle();

    expect(find.byType(VaquitaBootstrapScreen), findsNothing);
    expect(find.text('Weekend in CDMX'), findsOneWidget);
    expect(find.text('Apartment'), findsOneWidget);
  });

  testWidgets(
      'surfaces startup failures visibly and recovers when retrying initialization',
      (tester) async {
    var attempts = 0;

    await tester.pumpWidget(
      VaquitaApp(
        initializeStore: () async {
          attempts++;
          if (attempts == 1) {
            throw StateError('SQLite storage locked');
          }
          return DemoStore.seeded();
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(VaquitaBootstrapScreen), findsOneWidget);
    expect(find.text('No se pudo iniciar Vaquita MX'), findsOneWidget);
    expect(find.textContaining('SQLite storage locked'), findsOneWidget);
    expect(find.byKey(const Key('retry-startup-button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('retry-startup-button')));
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(find.byType(VaquitaBootstrapScreen), findsNothing);
    expect(find.text('Weekend in CDMX'), findsOneWidget);
  });

  testWidgets('applies cohesive light and dark themes with semantic tokens',
      (tester) async {
    await tester.pumpWidget(
      VaquitaApp(
        store: DemoStore.seeded(),
        themeMode: ThemeMode.light,
      ),
    );
    await tester.pumpAndSettle();

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
    var context = tester.element(find.byType(AppShell));
    expect(Theme.of(context).brightness, Brightness.light);
    expect(Theme.of(context).scaffoldBackgroundColor, VaquitaTheme.lightCanvas);
    expect(VaquitaColors.of(context).positive, VaquitaColors.light.positive);
    expect(scaffold.body, isNotNull);

    await tester.pumpWidget(
      VaquitaApp(
        store: DemoStore.seeded(),
        themeMode: ThemeMode.dark,
      ),
    );
    await tester.pumpAndSettle();

    context = tester.element(find.byType(AppShell));
    expect(Theme.of(context).brightness, Brightness.dark);
    expect(Theme.of(context).scaffoldBackgroundColor, VaquitaTheme.darkCanvas);
    expect(VaquitaColors.of(context).positive, VaquitaColors.dark.positive);

    // Navigate through Group Detail and Profile in dark mode.
    await tester.tap(find.byKey(const Key('group-cdmx-weekend')));
    await tester.pumpAndSettle();
    expect(find.text('Weekend in CDMX'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Perfil'));
    await tester.pumpAndSettle();
    expect(find.text('Modo local activo en este dispositivo'), findsOneWidget);
  });

  testWidgets(
      'remains usable without layout overflow at 1.6x text scale on compact phones',
      (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 640 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(360, 640),
          textScaler: TextScaler.linear(1.6),
        ),
        child: VaquitaApp(store: DemoStore.seeded()),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // Check Bandeja, Movimientos, Contactos, and Perfil at 1.6x text scale.
    for (final tab in ['Bandeja', 'Movimientos', 'Contactos', 'Perfil']) {
      await tester.tap(find.text(tab).last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    // Return to Inicio and open Group Detail + Add Expense sheet at 1.6x scale.
    await tester.tap(find.text('Inicio'));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const Key('dashboard-scroll')),
      const Offset(0, -450),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('group-cdmx-weekend')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('group-cdmx-weekend')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('add-expense-button')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('localizes new UI sections and net balance labels in English',
      (tester) async {
    await tester.pumpWidget(VaquitaApp(store: DemoStore.seeded()));
    await tester.pumpAndSettle();

    expect(find.textContaining('Neto'), findsOneWidget);

    await tester.tap(find.text('Perfil'));
    await tester.pumpAndSettle();
    expect(find.text('Preferencias e información'), findsOneWidget);

    await tester.tap(find.byKey(const Key('language-settings-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Inglés'));
    await tester.pumpAndSettle();

    expect(find.text('Preferences & info'), findsOneWidget);
    expect(find.text('Local mode active on this device'), findsOneWidget);

    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Net '), findsOneWidget);
  });
}
