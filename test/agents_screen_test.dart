import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplex/sessions/herd_controller.dart';
import 'package:multiplex/src/rust/api/agents.dart';
import 'package:multiplex/src/rust/api/herd_types.dart';
import 'package:multiplex/ui/computers/agents_screen.dart';

/// A computer's herdr that tests feed by hand.
class _Herd implements HerdLink {
  _Herd(this.now);

  HerdState now;
  Object? refuses;
  final told = StreamController<HerdState>.broadcast();
  final asked = <String>[];
  var output = 'Reading the code…';
  var watches = 0;
  var stopped = 0;

  void tell(HerdState next) {
    now = next;
    told.add(next);
  }

  @override
  Future<HerdState> state() async {
    if (refuses != null) throw refuses!;
    return now;
  }

  @override
  Future<(Stream<HerdState>, void Function())> watch() async {
    watches++;
    return (told.stream, () => stopped++);
  }

  @override
  Future<String> read(String session, String pane, int lines) async {
    asked.add('read $session $pane');
    return output;
  }

  @override
  Future<void> prompt(String session, String pane, String text) async => asked.add('prompt $session $pane: $text');

  @override
  Future<void> keys(String session, String pane, List<String> keys) async => asked.add('keys $session $pane: ${keys.join(' ')}');
}

HerdAgent _agent(
  String pane,
  AgentStatus status,
  String title, {
  String name = 'Claude',
  String session = 'default',
  String workspace = 'api',
  String folder = 'server',
}) => HerdAgent(session: session, workspace: workspace, tab: '1', pane: pane, name: name, status: status, title: title, folder: folder);

/// A herd whose inbox is [agents], already in the core's order.
HerdState _state(List<HerdAgent> agents, {bool available = true, List<HerdSession> sessions = const [], int? waiting}) =>
    HerdState(available: available, sessions: sessions, inbox: agents, waiting: waiting ?? agents.where((a) => a.status == AgentStatus.blocked).length);

HerdSession _session(String name, {int panes = 0}) => HerdSession(
  name: name,
  running: true,
  workspaces: [
    HerdWorkspace(
      id: 'w1',
      label: 'api',
      tabs: [
        HerdTab(
          id: 'w1:t1',
          label: '1',
          panes: [
            for (var i = 1; i <= panes; i++)
              HerdPane(id: 'w1:p$i', title: 'sam@desk:~', folder: '/home/sam', folderName: 'sam', focused: i == 1, status: AgentStatus.unknown),
          ],
        ),
      ],
    ),
  ],
);

void main() {
  Future<void> open(WidgetTester tester, _Herd herd, {List<String>? terminals}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AgentsScreen(
          title: 'Desk',
          link: herd,
          onOpenTerminal: (_, session, pane) async => terminals?.add('$session/$pane'),
          onOpenHerdr: (_, session) async => terminals?.add('herdr of $session'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('the inbox is in the order the core gives, under a heading per state', (tester) async {
    final herd = _Herd(
      _state([
        _agent('w1:p3', AgentStatus.blocked, 'Allow this command?', name: 'codex', workspace: 'web', folder: 'web'),
        _agent('w1:p4', AgentStatus.done, 'Tests fixed'),
        _agent('w1:p1', AgentStatus.working, 'Refactor the parser'),
        _agent('w2:p1', AgentStatus.working, 'Write the guide', folder: 'docs'),
      ]),
    );
    await open(tester, herd);
    expect(find.text('Agents on Desk'), findsOneWidget);
    final order = ['Needs you · 1', 'Allow this command?', 'Done · 1', 'Tests fixed', 'Working · 2', 'Refactor the parser', 'Write the guide'];
    final tops = [for (final text in order) tester.getTopLeft(find.text(text)).dy];
    expect(tops, [...tops]..sort(), reason: 'top to bottom in that order');
    expect(find.text('codex · web'), findsOneWidget, reason: 'the folder is not repeated when it is the workspace');
    expect(find.text('Claude · api · server'), findsNWidgets(2));
    expect(find.text('Claude · api · docs'), findsOneWidget);
    expect(herd.watches, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(herd.stopped, 1, reason: 'leaving the screen stops the listening');
  });

  testWidgets('the list follows the computer as it tells, without asking again', (tester) async {
    final herd = _Herd(_state([_agent('w1:p1', AgentStatus.working, 'Refactor the parser')]));
    await open(tester, herd);
    expect(find.text('Working · 1'), findsOneWidget);
    expect(find.text('Needs you · 1'), findsNothing);
    herd.tell(_state([_agent('w1:p1', AgentStatus.blocked, 'Refactor the parser')]));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Needs you · 1'), findsOneWidget);
    expect(find.text('Working · 1'), findsNothing);
    herd.tell(_state([], sessions: [_session('default', panes: 2)]));
    await tester.pump();
    expect(find.text('No agents are running'), findsOneWidget);
    expect(find.textContaining('2 terminals open'), findsOneWidget);
    expect(herd.asked, isEmpty, reason: 'nothing was asked of the computer for any of this');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('with several sessions each agent says which it is in', (tester) async {
    final herd = _Herd(_state([_agent('w1:p1', AgentStatus.idle, 'Waiting for work', session: 'night')], sessions: [_session('default'), _session('night')]));
    await open(tester, herd);
    expect(find.text('Idle · 1'), findsOneWidget);
    expect(find.text('Claude · api · server · night'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets("herdr's own screen is one tap away: at once with one session, by name with several", (tester) async {
    final terminals = <String>[];
    final one = _Herd(_state([_agent('w1:p1', AgentStatus.idle, 'Waiting for work')], sessions: [_session('default')]));
    await open(tester, one, terminals: terminals);
    await tester.tap(find.byTooltip("Open herdr's own screen"));
    expect(terminals, ['herdr of default']);
    await tester.pumpWidget(const SizedBox.shrink());

    terminals.clear();
    final two = _Herd(_state([_agent('w1:p1', AgentStatus.idle, 'Waiting for work')], sessions: [_session('default'), _session('night')]));
    await open(tester, two, terminals: terminals);
    await tester.tap(find.byTooltip("Open herdr's own screen"));
    await tester.pumpAndSettle();
    expect(terminals, isEmpty, reason: 'which one is asked first');
    await tester.tap(find.text('night'));
    await tester.pumpAndSettle();
    expect(terminals, ['herdr of night']);
    await tester.pumpWidget(const SizedBox.shrink());

    // Nothing to open where herdr runs nothing.
    final none = _Herd(_state([], available: false));
    await open(tester, none);
    expect(find.byTooltip("Open herdr's own screen"), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('everything herdr holds: sessions, workspaces, tabs, and plain terminals too', (tester) async {
    final terminals = <String>[];
    HerdPane pane(String id, String title, {String? agent, AgentStatus status = AgentStatus.unknown, String folder = 'api'}) =>
        HerdPane(id: id, title: title, folder: '/home/sam/code/$folder', folderName: folder, focused: false, agent: agent, status: status);
    final herd = _Herd(
      _state(
        [_agent('w1:p3', AgentStatus.blocked, 'Allow this command?', name: 'codex')],
        sessions: [
          HerdSession(
            name: 'default',
            running: true,
            workspaces: [
              HerdWorkspace(
                id: 'w1',
                label: 'api',
                tabs: [
                  HerdTab(id: 'w1:t1', label: '1', panes: [pane('w1:p2', 'sam@desk:~/code/api')]),
                  HerdTab(
                    id: 'w1:t2',
                    label: 'review',
                    panes: [pane('w1:p3', 'Allow this command?', agent: 'codex', status: AgentStatus.blocked)],
                  ),
                ],
              ),
              HerdWorkspace(
                id: 'w2',
                label: '',
                tabs: [
                  HerdTab(
                    id: 'w2:t1',
                    label: '1',
                    panes: [pane('w2:p1', '', folder: 'notes')],
                  ),
                ],
              ),
            ],
          ),
          const HerdSession(name: 'night', running: false, workspaces: []),
        ],
      ),
    );
    await open(tester, herd, terminals: terminals);
    await tester.tap(find.text('Everything'));
    await tester.pumpAndSettle();
    final order = ['default', 'api · 1', 'sam@desk:~/code/api', 'api · review', 'Allow this command?', 'w2', 'Terminal', 'night · not running'];
    final tops = [for (final text in order) tester.getTopLeft(find.text(text)).dy];
    expect(tops, [...tops]..sort(), reason: "in herdr's own order, a workspace with one tab under its name alone");
    expect(find.text('Terminal · api'), findsOneWidget);
    expect(find.text('codex · Needs you · api'), findsOneWidget);
    expect(find.text('Terminal · notes'), findsOneWidget);

    // A plain terminal opens as a terminal, at once.
    await tester.tap(find.text('sam@desk:~/code/api'));
    await tester.pump();
    expect(terminals, ['default/w1:p2']);
    // An agent's pane opens the agent.
    herd.output = 'Run it?';
    await tester.tap(find.text('Allow this command?'));
    await tester.pumpAndSettle();
    expect(find.text('Run it?'), findsOneWidget);
    expect(find.byTooltip('Send'), findsOneWidget);
    Navigator.of(tester.element(find.byTooltip('Send'))).pop();
    await tester.pumpAndSettle();
    // A session that is not running starts when its screen is opened.
    terminals.clear();
    await tester.tap(find.text('Start'));
    expect(terminals, ['herdr of night']);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('one running session with nothing open says so, without a heading of its own', (tester) async {
    final herd = _Herd(
      _state(
        [],
        sessions: [const HerdSession(name: 'default', running: true, workspaces: [])],
      ),
    );
    await open(tester, herd);
    await tester.tap(find.text('Everything'));
    await tester.pumpAndSettle();
    expect(find.text('Nothing is open in it.'), findsOneWidget);
    expect(find.text('default'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a computer without herdr, and one that does not answer', (tester) async {
    final none = _Herd(_state([], available: false));
    await open(tester, none);
    expect(find.text('herdr is not on this computer'), findsOneWidget);
    expect(find.text('Everything'), findsNothing, reason: 'no tabs over nothing');
    await tester.pumpWidget(const SizedBox.shrink());

    final herd = _Herd(_state([_agent('w1:p1', AgentStatus.done, 'Tests fixed')]))
      ..refuses = Exception('This computer does not have the Multiplex package (or it is an old one). Install it there, then try again.');
    await open(tester, herd);
    expect(find.textContaining('does not have the Multiplex package'), findsOneWidget);
    expect(find.text('Tests fixed'), findsNothing);
    herd.refuses = null;
    await tester.tap(find.text('Try again'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Tests fixed'), findsOneWidget);
    expect(find.textContaining('does not have the Multiplex package'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('when the computer stops telling, it is asked again shortly', (tester) async {
    final herd = _Herd(_state([_agent('w1:p1', AgentStatus.working, 'Refactor the parser')]));
    final controller = HerdController(herd, retryAfter: const Duration(seconds: 2));
    await controller.start();
    expect(herd.watches, 1);
    // The connection went: the stream ends.
    await herd.told.close();
    await tester.pump(const Duration(seconds: 1));
    expect(herd.watches, 1);
    await tester.pump(const Duration(seconds: 2));
    expect(herd.watches, 2, reason: 'listening again');
    expect(controller.state!.inbox.single.title, 'Refactor the parser');
    controller.dispose();
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('an agent opens to what it wrote, takes keys and an answer, and reads again when its state changes', (tester) async {
    final terminals = <String>[];
    final herd = _Herd(_state([_agent('w1:p3', AgentStatus.blocked, 'Allow this command?', name: 'codex')]))..output = 'Run `make test`?\n 1. Yes\n 2. No';
    await open(tester, herd, terminals: terminals);
    await tester.tap(find.text('Allow this command?'));
    await tester.pumpAndSettle();
    expect(find.textContaining('1. Yes'), findsOneWidget);
    expect(find.text('Needs you · codex · server'), findsOneWidget);
    expect(herd.asked, ['read default w1:p3']);

    // A choice by its key; then what the pane shows is read again.
    herd.asked.clear();
    herd.output = 'Running make test…';
    await tester.tap(find.byTooltip('Press 1'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(herd.asked, ['keys default w1:p3: 1', 'read default w1:p3']);
    expect(find.text('Running make test…'), findsOneWidget);

    // Words for it: sent as written, and the line is empty again.
    herd.asked.clear();
    await tester.enterText(find.byType(TextField), '  Also run the linter; it\'s "quick".  ');
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(herd.asked, ['prompt default w1:p3: Also run the linter; it\'s "quick".', 'read default w1:p3']);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
    // An empty line sends nothing.
    herd.asked.clear();
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    expect(herd.asked, isEmpty);

    // The computer tells it finished: its state shows, and its words are read again.
    herd.output = 'All 12 tests pass.';
    herd.tell(_state([_agent('w1:p3', AgentStatus.done, 'Tests pass', name: 'codex')]));
    await tester.pump();
    await tester.pump();
    expect(herd.asked, ['read default w1:p3']);
    expect(find.text('All 12 tests pass.'), findsOneWidget);
    expect(find.text('Done · codex · server'), findsOneWidget);

    // The terminal is one tap away.
    await tester.tap(find.byTooltip('Open its terminal'));
    expect(terminals, ['default/w1:p3']);

    // It left: said, and nothing more can be sent to it.
    herd.tell(_state([]));
    await tester.pump();
    await tester.pump();
    expect(find.text('This agent is no longer running'), findsOneWidget);
    expect(tester.widget<IconButton>(find.ancestor(of: find.byIcon(Icons.send), matching: find.byType(IconButton))).onPressed, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('while an agent works its words are followed; once it waits, only on news', (tester) async {
    final herd = _Herd(_state([_agent('w1:p1', AgentStatus.working, 'Refactor the parser')]));
    await open(tester, herd);
    await tester.tap(find.text('Refactor the parser'));
    await tester.pumpAndSettle();
    herd.asked.clear();
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));
    expect(herd.asked, ['read default w1:p1', 'read default w1:p1']);
    herd.tell(_state([_agent('w1:p1', AgentStatus.blocked, 'Refactor the parser')]));
    await tester.pump();
    await tester.pump();
    herd.asked.clear();
    await tester.pump(const Duration(seconds: 6));
    expect(herd.asked, isEmpty, reason: 'a waiting agent writes nothing more');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('a request the computer refuses is said in the sheet', (tester) async {
    final herd = _RefusingHerd(_state([_agent('w1:p1', AgentStatus.blocked, 'Allow this?')]));
    await open(tester, herd);
    await tester.tap(find.text('Allow this?'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Press Escape'));
    await tester.pump();
    await tester.pump();
    expect(find.text('This phone may not use the terminal on this computer.'), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 3));
  });
}

/// A computer that lets this phone look but not type.
class _RefusingHerd extends _Herd {
  _RefusingHerd(super.now);

  @override
  Future<void> keys(String session, String pane, List<String> keys) async => throw Exception('This phone may not use the terminal on this computer.');
}
