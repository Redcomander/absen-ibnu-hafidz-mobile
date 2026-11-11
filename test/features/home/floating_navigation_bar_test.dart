import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibnu_hafidz_flutter/core/theme/app_theme.dart';
import 'package:ibnu_hafidz_flutter/features/home/floating_navigation_bar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (Platform.environment['NAV_PREVIEW_PATH'] == null) return;
    await (FontLoader(
      'PlusJakartaSans',
    )..addFont(rootBundle.load('assets/fonts/PlusJakartaSans.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  const destinations = [
    NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Beranda'),
    NavigationDestination(
      icon: Icon(Icons.calendar_month_rounded),
      label: 'Jadwal',
    ),
    NavigationDestination(
      icon: Icon(Icons.query_stats_rounded),
      label: 'Rekapan',
    ),
    NavigationDestination(icon: Icon(Icons.tune_rounded), label: 'Pengaturan'),
  ];
  for (final count in [3, 4]) {
    testWidgets(
      '$count menus fit narrow screens with large text and animate selection',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var selected = 0;
        final boundary = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
              child: StatefulBuilder(
                builder: (context, setState) => Scaffold(
                  body: const Center(child: Text('IBNU HAFIDZ')),
                  bottomNavigationBar: RepaintBoundary(
                    key: boundary,
                    child: FloatingNavigationBar(
                      selectedIndex: selected,
                      destinations: destinations.take(count).toList(),
                      onSelected: (i) => setState(() => selected = i),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final active = find.byKey(const ValueKey('nav-active-indicator'));
        final before = tester.getCenter(active).dx;
        await tester.tap(find.byKey(const ValueKey('nav-Jadwal')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 190));
        final midway = tester.getCenter(active).dx;
        await tester.pumpAndSettle();
        final after = tester.getCenter(active).dx;
        expect(midway, greaterThan(before));
        expect(midway, lessThan(after));
        expect(selected, 1);
        expect(tester.takeException(), isNull);
        final output = Platform.environment['NAV_PREVIEW_PATH'];
        if (output != null && count == 4) {
          await tester.runAsync(() async {
            final image =
                await (boundary.currentContext!.findRenderObject()
                        as RenderRepaintBoundary)
                    .toImage(pixelRatio: 3);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File(output).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets(
    'long jumps crossfade only endpoints and rapid taps keep position',
    (tester) async {
      var selected = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: StatefulBuilder(
            builder: (context, setState) => Scaffold(
              bottomNavigationBar: FloatingNavigationBar(
                selectedIndex: selected,
                destinations: destinations,
                onSelected: (i) => setState(() => selected = i),
              ),
            ),
          ),
        ),
      );
      final indicator = find.byKey(const ValueKey('nav-active-indicator'));
      await tester.tap(find.byKey(const ValueKey('nav-Pengaturan')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 170));
      expect(
        find.descendant(
          of: indicator,
          matching: find.byIcon(Icons.calendar_month_rounded),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: indicator,
          matching: find.byIcon(Icons.query_stats_rounded),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: indicator,
          matching: find.byIcon(Icons.home_outlined),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: indicator,
          matching: find.byIcon(Icons.tune_rounded),
        ),
        findsOneWidget,
      );
      final beforeRetarget = tester.getCenter(indicator).dx;
      await tester.tap(find.byKey(const ValueKey('nav-Rekapan')));
      await tester.pump();
      expect(tester.getCenter(indicator).dx, closeTo(beforeRetarget, .01));
      await tester.pumpAndSettle();
      expect(selected, 2);
      expect(
        tester.getCenter(indicator).dx,
        closeTo(
          tester.getCenter(find.byKey(const ValueKey('nav-Rekapan'))).dx,
          .01,
        ),
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'reduced motion selects immediately and exposes selected semantics',
    (tester) async {
      final semantics = tester.ensureSemantics();
      var selected = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: StatefulBuilder(
              builder: (context, setState) => Scaffold(
                bottomNavigationBar: FloatingNavigationBar(
                  selectedIndex: selected,
                  destinations: destinations,
                  onSelected: (i) => setState(() => selected = i),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('nav-Pengaturan')));
      await tester.pumpAndSettle();
      expect(selected, 3);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Pengaturan').first),
        matchesSemantics(
          label: 'Pengaturan',
          isButton: true,
          isSelected: true,
          hasSelectedState: true,
          hasTapAction: true,
          hasFocusAction: true,
          isFocusable: true,
        ),
      );
      expect(tester.binding.transientCallbackCount, 0);
      semantics.dispose();
    },
  );
}
