import 'package:dynamic_notification_island/dynamic_notification_island.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const notice = DynamicIslandNotice(
  id: 'cierre',
  title: 'Revisa el cierre de caja',
  message: 'Hay una diferencia en el arqueo.',
);
final pill = find.byKey(const ValueKey('dynamic-island'));
final panel = find.byKey(const ValueKey('dynamic-island-notice'));

Widget frame({
  DynamicIslandNotice? current = notice,
  Object? announcement,
  Duration? duration,
  bool quiet = false,
  bool screenReader = false,
  double scale = 1,
  VoidCallback? open,
  VoidCallback? background,
}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(
      disableAnimations: quiet,
      accessibleNavigation: screenReader,
      textScaler: TextScaler.linear(scale),
    ),
    child: Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        centerTitle: true,
        title: DynamicNotificationIsland(
          notice: current,
          announcement: announcement,
          onOpen: open ?? () {},
          duration: duration,
        ),
        actions: const [SizedBox(width: 44)],
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: background ?? () {},
        child: const SizedBox.expand(),
      ),
    ),
  ),
);

void main() {
  test('resting island matches the iPhone Pro / Pro Max hardware island', () {
    final iphone = statusBarIslandGeometry(
      const MediaQueryData(
        size: Size(440, 956),
        padding: EdgeInsets.only(top: 62),
      ),
    )!;
    expect(iphone.size, const Size(126, 37));
    expect(iphone.top, 11);
    final android = statusBarIslandGeometry(
      const MediaQueryData(size: Size(412, 915), padding: EdgeInsets.only(top: 40)),
    )!;
    expect(android.size.height, 34);
    expect(android.size.aspectRatio, closeTo(126 / 37, .001));
    expect(
      statusBarIslandGeometry(const MediaQueryData(size: Size(1280, 800))),
      isNull,
    );
  });

  testWidgets('in the status strip it rests bare and widens for a notice', (
    tester,
  ) async {
    Widget strip(DynamicIslandNotice? current) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: DynamicNotificationIsland(
            notice: current,
            onOpen: () {},
            compactSize: const Size(126, 37),
            placement: IslandPlacement.statusBar,
          ),
        ),
      ),
    );
    await tester.pumpWidget(strip(null));
    await tester.pumpAndSettle();
    expect(tester.getSize(pill), const Size(126, 37));
    await tester.pumpWidget(strip(notice));
    await tester.pumpAndSettle();
    expect(tester.getSize(pill), const Size(190, 37));
  });

  testWidgets(
    'compact island expands, leaves the page interactive, and opens the inbox',
    (tester) async {
      var opened = 0;
      var tapped = 0;
      await tester.pumpWidget(
        frame(open: () => opened++, background: () => tapped++),
      );
      expect(panel, findsNothing);
      await tester.tap(pill);
      await tester.pumpAndSettle();
      expect(panel, findsOneWidget);
      expect(
        tester.getTopLeft(panel).dy,
        greaterThan(tester.getCenter(pill).dy),
      );
      await tester.tapAt(const Offset(10, 300));
      expect(tapped, 1);
      await tester.tap(find.text(notice.title));
      await tester.pumpAndSettle();
      expect(opened, 1);
      expect(panel, findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('new authorized notice, invalidation and time limit', (
    tester,
  ) async {
    await tester.pumpWidget(frame(duration: const Duration(seconds: 3)));
    await tester.pumpWidget(
      frame(announcement: 1, duration: const Duration(seconds: 3)),
    );
    await tester.pumpAndSettle();
    expect(panel, findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(panel, findsNothing);
    await tester.tap(pill);
    await tester.pumpAndSettle();
    await tester.pumpWidget(frame(current: null));
    expect(find.text(notice.title), findsNothing);
    await tester.pumpAndSettle();
    expect(panel, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'screen reader keeps the notice until dismissal and large text fits',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 650);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        frame(
          announcement: 1,
          duration: const Duration(seconds: 1),
          quiet: true,
          screenReader: true,
          scale: 2,
        ),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 6));
      expect(panel, findsOneWidget);
      expect(tester.getRect(panel).width, lessThanOrEqualTo(320));
      await tester.tap(find.byTooltip('Close'));
      await tester.pump();
      expect(panel, findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('swipe closes without opening; empty island opens the inbox', (
    tester,
  ) async {
    var opened = 0;
    await tester.pumpWidget(frame(announcement: 1, open: () => opened++));
    await tester.pumpAndSettle();
    await tester.drag(panel, const Offset(0, -65));
    await tester.pumpAndSettle();
    expect(panel, findsNothing);
    expect(opened, 0);
    await tester.pumpWidget(frame(current: null, open: () => opened++));
    await tester.tap(pill);
    expect(opened, 1);
    expect(tester.takeException(), isNull);
  });
}
