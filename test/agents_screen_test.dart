import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multiplex/sessions/herd_controller.dart';
import 'package:multiplex/src/rust/api/agents.dart';
import 'package:multiplex/src/rust/api/herd_types.dart';
import 'package:multiplex/ui/computers/agents_screen.dart';

/// A computer's session server that tests feed by hand.
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

  /// What the agent asks by choice, as the computer reads it off the
  /// screen; and why an answer is refused, when it is.
  HerdAsked? asks;
  Object? answerRefused;

  @override
  Future<HerdText> read(String session, String pane, int lines) async {
    asked.add('read $session $pane');
    return HerdText(text: output, asked: asks);
  }

  @override
  Future<void> answerChoice(String session, String pane, String mark, String choice) async {
    asked.add('answer $session $pane [$mark]: choice $choice');
    if (answerRefused != null) throw answerRefused!;
  }

  @override
  Future<void> answerText(String session, String pane, String mark, String text) async => asked.add('answer $session $pane [$mark]: $text');

  @override
  Future<void> prompt(String session, String pane, String text) async => asked.add('prompt $session $pane: $text');

  @override
  Future<void> keys(String session, String pane, List<String> keys) async => asked.add('keys $session $pane: ${keys.join(' ')}');

  /// The agents this computer has; null: it cannot say.
  List<HerdKind>? has = const [HerdKind(name: 'claude', installed: true), HerdKind(name: 'codex', installed: true), HerdKind(name: 'amp', installed: false)];
  Object? startFails;

  @override
  Future<List<HerdKind>> kinds() async {
    asked.add('kinds');
    if (has == null) throw Exception('The computer did not answer.');
    return has!;
  }

  @override
  Future<HerdMade> newTab(String session, String workspace, String label) async {
    asked.add('new tab $session $workspace "$label"');
    return const HerdMade(workspace: '', tab: 'w1:t9', pane: 'w1:p9');
  }

  @override
  Future<void> start(String session, String pane, String kind) async {
    asked.add('start $session $pane $kind');
    if (startFails != null) throw startFails!;
  }

  @override
  Future<void> closePane(String session, String pane) async => asked.add('close $session $pane');

  @override
  Future<void> rename(String session, String workspace, String label) async => asked.add('rename $session $workspace "$label"');

  /// The agents that run where the phone cannot reach.
  List<HerdOutside> runsOutside = const [];

  @override
  Future<List<HerdOutside>> outside() async => runsOutside;

  @override
  Future<HerdMade> carryOn(String session, String folder, String kind) async {
    asked.add('carry on $session $folder $kind');
    return const HerdMade(workspace: 'w7', tab: 'w7:t9', pane: 'w7:p9');
  }

  /// The folders the computer offers; null: it cannot say.
  List<HerdPlace>? offers = const [
    HerdPlace(path: '/home/sam/code/api', shown: '~/code/api', name: 'api', project: true),
    HerdPlace(path: '/home/sam/notes', shown: '~/notes', name: 'notes', project: false),
  ];

  @override
  Future<List<HerdPlace>> places() async {
    asked.add('places');
    if (offers == null) throw Exception('The computer did not answer.');
    return offers!;
  }

  @override
  Future<List<HerdPlace>> foldersIn(String folder) async {
    asked.add('folders in $folder');
    return [HerdPlace(path: '$folder/drafts', shown: '~/notes/drafts', name: 'drafts', project: false)];
  }

  @override
  Future<HerdMade> newWorkspace(String session, String folder, String label) async {
    asked.add('new workspace $session $folder "$label"');
    return const HerdMade(workspace: 'w7', tab: 'w7:t1', pane: 'w7:p1');
  }
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
  Future<void> open(WidgetTester tester, _Herd herd, {List<String>? terminals, List<String>? visited, ({String session, String pane})? openAt}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AgentsScreen(
          title: 'Desk',
          link: herd,
          onOpenTerminal: (_, session, pane) async => terminals?.add('$session/$pane'),
          onStartSession: (_, session) async => terminals?.add('start of $session'),
          openAt: openAt,
          onVisited: (session, pane, title, agent) => visited?.add('$session/$pane "$title" ${agent.isEmpty ? '(terminal)' : agent}'),
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

  testWidgets('a swipe across an agent goes straight to its terminal, and the agent stays in the list', (tester) async {
    final terminals = <String>[];
    final herd = _Herd(_state([_agent('w1:p3', AgentStatus.blocked, 'Allow this command?')]));
    await open(tester, herd, terminals: terminals);
    await tester.drag(find.text('Allow this command?'), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(terminals, ['default/w1:p3']);
    expect(find.text('Allow this command?'), findsOneWidget);
    expect(herd.asked.where((what) => what.startsWith('read')), isEmpty, reason: 'its sheet was not opened on the way');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 3));
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
    expect(find.textContaining('2 terminals are open'), findsOneWidget);
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

  testWidgets('everything the computer keeps: sessions, workspaces, tabs, and plain terminals too', (tester) async {
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
    final order = ['default', 'api · 1', 'sam@desk:~/code/api', 'api · review', 'Allow this command?', 'w2', 'Terminal'];
    final tops = [for (final text in order) tester.getTopLeft(find.text(text)).dy];
    expect(tops, [...tops]..sort(), reason: "in the computer's own order, a workspace with one tab under its name alone");
    // The running session ends with the way to add to it, by name since there are two.
    expect(find.text('As a new workspace in default'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Open a folder')).dy, greaterThan(tops.last));
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
    // A session that is not running comes last, with nothing to add to it
    // until it is started; opening its screen is what starts it.
    await tester.drag(find.text('Open a folder'), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(find.text('night · not running'), findsOneWidget);
    expect(tester.widgetList(find.text('Open a folder')).length, lessThanOrEqualTo(1), reason: 'only the running session offers it');
    terminals.clear();
    await tester.tap(find.text('Start'));
    expect(terminals, ['start of night']);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 3));
  });

  group('making and closing', () {
    HerdState one() => _state(
      [],
      sessions: [
        const HerdSession(
          name: 'default',
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
                    HerdPane(
                      id: 'w1:p1',
                      title: 'sam@desk:~/code/api',
                      folder: '/home/sam/code/api',
                      folderName: 'api',
                      focused: true,
                      status: AgentStatus.unknown,
                    ),
                  ],
                ),
                HerdTab(
                  id: 'w1:t2',
                  label: 'notes',
                  panes: [
                    HerdPane(
                      id: 'w1:p2',
                      title: 'Refactor',
                      folder: '/home/sam/code/api',
                      folderName: 'api',
                      focused: false,
                      agent: 'Claude',
                      status: AgentStatus.working,
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ],
    );

    Future<void> everything(WidgetTester tester, _Herd herd, List<String> terminals, List<String> visited) async {
      await open(tester, herd, terminals: terminals, visited: visited);
      await tester.tap(find.text('Everything'));
      await tester.pumpAndSettle();
    }

    testWidgets('a new terminal in a workspace: one tap to ask, one to choose, and the phone is in it', (tester) async {
      final terminals = <String>[];
      final visited = <String>[];
      final herd = _Herd(one());
      await everything(tester, herd, terminals, visited);
      // The plus is on the workspace's first heading only.
      expect(find.byTooltip('New in api'), findsOneWidget);
      await tester.tap(find.byTooltip('New in api'));
      await tester.pumpAndSettle();
      expect(find.text('New in api'), findsOneWidget);
      expect(find.text('Claude'), findsOneWidget, reason: 'the agents this computer has, by name');
      expect(find.text('Codex'), findsOneWidget);
      // One that would download itself first says so, after those that are there.
      expect(find.text('Starts in a new tab'), findsNWidgets(2));
      expect(
        find.descendant(
          of: find.ancestor(of: find.text('Amp'), matching: find.byType(ListTile)),
          matching: find.text('Not installed yet: the first start downloads it'),
        ),
        findsOneWidget,
      );
      expect(tester.getTopLeft(find.text('Codex')).dy, lessThan(tester.getTopLeft(find.text('Amp')).dy));
      await tester.tap(find.text('Terminal'));
      await tester.pumpAndSettle();
      expect(herd.asked, ['kinds', 'new tab default w1 ""']);
      expect(terminals, ['default/w1:p9']);
      expect(visited.last, 'default/w1:p9 "" (terminal)');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('a new agent: a tab named after it, the agent started in it, then its terminal', (tester) async {
      final terminals = <String>[];
      final visited = <String>[];
      final herd = _Herd(one());
      await everything(tester, herd, terminals, visited);
      await tester.tap(find.byTooltip('New in api'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Codex'));
      await tester.pumpAndSettle();
      expect(herd.asked, ['kinds', 'new tab default w1 "codex"', 'start default w1:p9 codex']);
      expect(terminals, ['default/w1:p9']);
      expect(visited.last, 'default/w1:p9 "Codex" codex');
      await tester.pump(const Duration(seconds: 5));

      // An agent that does not start is said; the tab is still opened, to see why.
      herd.asked.clear();
      terminals.clear();
      herd.startFails = Exception('Herdr: agent_not_ready');
      await tester.tap(find.byTooltip('New in api'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Claude'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Herdr: agent_not_ready'), findsOneWidget);
      expect(herd.asked, ['new tab default w1 "claude"', 'start default w1:p9 claude'], reason: 'which agents there are is asked once');
      expect(terminals, ['default/w1:p9']);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('with no agent installed, or no answer, a terminal can still be made', (tester) async {
      final herd = _Herd(one())..has = [];
      await everything(tester, herd, [], []);
      await tester.tap(find.byTooltip('New in api'));
      await tester.pumpAndSettle();
      expect(find.text('None of the agents Multiplex knows is installed on this computer.'), findsOneWidget);
      expect(find.text('Terminal'), findsOneWidget);
      Navigator.of(tester.element(find.text('Terminal'))).pop();
      await tester.pumpAndSettle();
      expect(herd.asked, ['kinds'], reason: 'leaving the sheet makes nothing');
      await tester.pumpWidget(const SizedBox.shrink());

      final silent = _Herd(one())..has = null;
      await everything(tester, silent, [], []);
      await tester.tap(find.byTooltip('New in api'));
      await tester.pumpAndSettle();
      expect(find.text('The computer did not answer.'), findsWidgets);
      expect(find.text('Terminal'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('a folder of the computer opens as a workspace, and then what to have in it is asked', (tester) async {
      final terminals = <String>[];
      final visited = <String>[];
      final herd = _Herd(one());
      await everything(tester, herd, terminals, visited);
      expect(find.text('As a new workspace'), findsOneWidget, reason: 'one session needs no name');
      await tester.tap(find.text('Open a folder'));
      await tester.pumpAndSettle();
      // The folders worth offering, each with where it is; a project is marked.
      expect(find.text('~/code/api'), findsOneWidget);
      expect(find.text('~/notes'), findsOneWidget);
      expect(find.byIcon(Icons.source_outlined), findsOneWidget);
      await tester.tap(find.text('api'));
      await tester.pumpAndSettle();
      expect(herd.asked, ['places', 'new workspace default /home/sam/code/api "api"', 'kinds']);
      // It comes with a terminal: that one is used, no further tab is made.
      expect(find.text('api is open. What in it?'), findsOneWidget);
      expect(find.text('The shell it came with'), findsOneWidget);
      await tester.tap(find.text('Terminal'));
      await tester.pumpAndSettle();
      expect(herd.asked.where((a) => a.startsWith('new tab')), isEmpty);
      expect(terminals, ['default/w7:p1']);
      expect(visited.last, 'default/w7:p1 "api" (terminal)');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('any folder can be reached by looking inside, and an agent starts in the new workspace itself', (tester) async {
      final terminals = <String>[];
      final herd = _Herd(one());
      await everything(tester, herd, terminals, []);
      await tester.tap(find.text('Open a folder'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Look inside notes'));
      await tester.pumpAndSettle();
      expect(herd.asked, ['places', 'folders in /home/sam/notes']);
      expect(find.text('~/notes'), findsOneWidget, reason: 'the heading says where this is');
      expect(find.text('notes'), findsOneWidget, reason: 'and first of all what it is called');
      expect(find.text('drafts'), findsOneWidget);
      expect(find.text('~/notes/drafts'), findsNothing, reason: 'inside a folder its folders need no path of their own');
      // Back to the offers, and in again.
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('~/code/api'), findsOneWidget);
      await tester.tap(find.byTooltip('Look inside notes'));
      await tester.pumpAndSettle();
      // The folder being looked at can itself be the one.
      await tester.tap(find.text('Open this one'));
      await tester.pumpAndSettle();
      expect(herd.asked.last, 'kinds');
      expect(herd.asked[herd.asked.length - 2], 'new workspace default /home/sam/notes "notes"');
      await tester.tap(find.text('Claude'));
      await tester.pumpAndSettle();
      expect(herd.asked.last, 'start default w7:p1 claude', reason: 'in the terminal the workspace came with');
      expect(terminals, ['default/w7:p1']);
      await tester.pump(const Duration(seconds: 5));

      // Leaving the second question keeps the workspace and opens nothing.
      terminals.clear();
      await tester.tap(find.text('Open a folder'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('api'));
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.text('api is open. What in it?'))).pop();
      await tester.pumpAndSettle();
      expect(terminals, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('a computer that cannot say which folders it has says so in the picker', (tester) async {
      final herd = _Herd(one())..offers = null;
      await everything(tester, herd, [], []);
      await tester.tap(find.text('Open a folder'));
      await tester.pumpAndSettle();
      expect(find.text('The computer did not answer.'), findsWidgets);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('an agent outside a kept terminal is listed, and its conversation continued in one that is', (tester) async {
      final terminals = <String>[];
      final herd = _Herd(one())
        ..runsOutside = const [
          HerdOutside(agent: 'claude', folder: '/home/sam/code/web', folderName: 'web', canContinue: true),
          HerdOutside(agent: 'amp', folder: '/home/sam/code/old', folderName: 'old', canContinue: false),
        ];
      await everything(tester, herd, terminals, []);
      expect(find.text('Running outside Multiplex'), findsOneWidget);
      expect(find.text('Claude in web'), findsOneWidget);
      // Asked about first, with why; "Not now" does nothing.
      await tester.tap(find.text('Claude in web'));
      await tester.pumpAndSettle();
      expect(find.text('Continue Claude here?'), findsOneWidget);
      expect(find.textContaining('two at once on one conversation'), findsOneWidget);
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(herd.asked.where((what) => what.startsWith('carry on')), isEmpty);
      // Continued: a new workspace on the computer, and the phone in front of it.
      await tester.tap(find.text('Claude in web'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue here'));
      await tester.pumpAndSettle();
      expect(herd.asked.where((what) => what.startsWith('carry on')), ['carry on default /home/sam/code/web claude']);
      expect(terminals, ['default/w7:p9']);
      // One whose way of carrying on is not known is only told of.
      await tester.tap(find.text('Amp in old'));
      await tester.pumpAndSettle();
      expect(find.text('Amp runs outside'), findsOneWidget);
      expect(find.text('Continue here'), findsNothing);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('a workspace takes another name', (tester) async {
      final herd = _Herd(one());
      await everything(tester, herd, [], []);
      await tester.tap(find.byTooltip('Rename api'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'api', reason: 'starting from the name it has');
      // The same name, or none, changes nothing.
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();
      expect(herd.asked, isEmpty);
      await tester.tap(find.byTooltip('Rename api'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '  the billing api ');
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();
      expect(herd.asked, ['rename default w1 "the billing api"']);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('closing a pane is asked about first', (tester) async {
      final herd = _Herd(one());
      await everything(tester, herd, [], []);
      await tester.longPress(find.text('Refactor'));
      await tester.pumpAndSettle();
      expect(find.text('Close this agent?'), findsOneWidget);
      expect(find.textContaining('What runs in it on the computer ends with it.'), findsOneWidget);
      await tester.tap(find.text('Keep it'));
      await tester.pumpAndSettle();
      expect(herd.asked, isEmpty);
      await tester.longPress(find.text('sam@desk:~/code/api'));
      await tester.pumpAndSettle();
      expect(find.text('Close this terminal?'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(herd.asked, ['close default w1:p1']);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 3));
    });
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

  group('continuing', () {
    HerdState herdWith({bool agentThere = true}) => _state(
      [if (agentThere) _agent('w1:p3', AgentStatus.blocked, 'Allow this command?', name: 'codex')],
      sessions: [
        HerdSession(
          name: 'default',
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
                    const HerdPane(id: 'w1:p2', title: 'sam@desk:~', folder: '/home/sam', folderName: 'sam', focused: true, status: AgentStatus.unknown),
                    if (agentThere)
                      const HerdPane(
                        id: 'w1:p3',
                        title: 'Allow this command?',
                        folder: '/srv/web',
                        folderName: 'web',
                        focused: false,
                        agent: 'codex',
                        status: AgentStatus.blocked,
                      ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ],
    );

    testWidgets('each agent or terminal opened is told, as the place to continue from', (tester) async {
      final visited = <String>[];
      final herd = _Herd(herdWith());
      await open(tester, herd, visited: visited, terminals: []);
      await tester.tap(find.text('Allow this command?'));
      await tester.pumpAndSettle();
      expect(visited, ['default/w1:p3 "Allow this command?" codex']);
      Navigator.of(tester.element(find.byTooltip('Send'))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Everything'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('sam@desk:~'));
      await tester.pump();
      expect(visited.last, 'default/w1:p2 "sam@desk:~" (terminal)');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('asked to continue with an agent, it opens that agent by itself', (tester) async {
      final herd = _Herd(herdWith())..output = 'Run `make test`?';
      await open(tester, herd, openAt: (session: 'default', pane: 'w1:p3'));
      await tester.pumpAndSettle();
      expect(find.text('Run `make test`?'), findsOneWidget);
      expect(find.byTooltip('Send'), findsOneWidget);
      // Only once: a later change of the herd does not open it again.
      Navigator.of(tester.element(find.byTooltip('Send'))).pop();
      await tester.pumpAndSettle();
      herd.tell(herdWith());
      await tester.pumpAndSettle();
      expect(find.byTooltip('Send'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('asked to continue with a plain terminal, it opens that terminal', (tester) async {
      final terminals = <String>[];
      await open(tester, _Herd(herdWith()), terminals: terminals, openAt: (session: 'default', pane: 'w1:p2'));
      await tester.pumpAndSettle();
      expect(terminals, ['default/w1:p2']);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('what is no longer there is said, and the list is shown instead', (tester) async {
      final terminals = <String>[];
      await open(tester, _Herd(herdWith(agentThere: false)), terminals: terminals, openAt: (session: 'default', pane: 'w1:p3'));
      await tester.pump();
      expect(find.text('That one is no longer running. Here is what is.'), findsOneWidget);
      expect(find.text('No agents are running'), findsOneWidget);
      expect(terminals, isEmpty);
      expect(find.byTooltip('Send'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 5));
    });
  });

  testWidgets('a computer whose package is too old, and one that does not answer', (tester) async {
    final none = _Herd(_state([], available: false));
    await open(tester, none);
    expect(find.text('This computer does not keep sessions yet'), findsOneWidget);
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
    expect(find.text('It is working. Tell it more…'), findsOneWidget, reason: 'a prompt can be sent while it works');
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

  testWidgets("an agent's choices are buttons in its own words; an answer goes to that question only", (tester) async {
    const asks = HerdAsked(
      question: 'Bash command\n\nmake test\n\nDo you want to proceed?',
      choices: [
        HerdChoice(key: '1', label: 'Yes'),
        HerdChoice(key: '2', label: "Yes, and don't ask again for make commands"),
        HerdChoice(key: '3', label: 'No, and tell Claude what to do differently'),
      ],
      mark: '0123456789abcdef',
    );
    final herd = _Herd(_state([_agent('w1:p3', AgentStatus.blocked, 'Run the tests')]))
      ..output = 'Do you want to proceed?\n❯ 1. Yes'
      ..asks = asks;
    await open(tester, herd);
    await tester.tap(find.text('Run the tests'));
    await tester.pumpAndSettle();
    expect(find.text('Yes'), findsOneWidget);
    expect(find.text("Yes, and don't ask again for make commands"), findsOneWidget);
    expect(find.text('No, and tell Claude what to do differently'), findsOneWidget);
    expect(find.byTooltip('Press 1'), findsOneWidget, reason: 'the keys are still there, for what is not a choice');

    // One tap: sent with the mark of the question it was shown for. The
    // buttons go at once (a second tap must not answer what comes next),
    // and what the agent shows now is read.
    herd.asked.clear();
    herd
      ..asks = null
      ..output = 'Running make test…';
    await tester.tap(find.text('No, and tell Claude what to do differently'));
    await tester.pump();
    expect(find.text('Yes'), findsNothing);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(herd.asked, ['answer default w1:p3 [0123456789abcdef]: choice 3', 'read default w1:p3']);
    expect(find.text('Running make test…'), findsOneWidget);

    // It asks something else by now (it was answered at the computer):
    // the computer sends nothing and says so; the new question shows.
    const next = HerdAsked(
      question: 'Edit file\n\nsrc/main.rs',
      choices: [
        HerdChoice(key: '1', label: 'Yes'),
        HerdChoice(key: '2', label: 'No'),
      ],
      mark: 'fedcba9876543210',
    );
    herd.asks = asks;
    await tester.tap(find.byTooltip('Read again'));
    await tester.pump();
    await tester.pump();
    herd.asked.clear();
    herd
      ..answerRefused = Exception('That is no longer what it asks. Nothing was sent.')
      ..asks = next;
    await tester.tap(find.text('Yes'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(herd.asked, ['answer default w1:p3 [0123456789abcdef]: choice 1', 'read default w1:p3']);
    expect(find.text('That is no longer what it asks. Nothing was sent.'), findsOneWidget, reason: 'it stays, though the screen was read again since');
    expect(find.text('No'), findsOneWidget, reason: 'the choices of what it asks now');
    expect(find.text("Yes, and don't ask again for make commands"), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('pictures for an agent are named in the answer by where they are on the computer', (tester) async {
    final herd = _Herd(_state([_agent('w1:p3', AgentStatus.idle, 'Design the page')]));
    final controller = HerdController(herd);
    await controller.start();
    var picked = <String>['/home/sam/inbox/from-phone-1-1-sketch.png', '/home/sam/in box/from-phone-1-2-photo.jpg'];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AgentSheet(herd: controller, session: 'default', pane: 'w1:p3', onOpenTerminal: () {}, attachPictures: () async => picked),
        ),
      ),
    );
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Make it like this');
    await tester.tap(find.byTooltip('Show it pictures'));
    await tester.pump();
    await tester.pump();
    // After the owner's words, a path with a blank in it quoted.
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Make it like this /home/sam/inbox/from-phone-1-1-sketch.png "/home/sam/in box/from-phone-1-2-photo.jpg" ',
    );
    herd.asked.clear();
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    expect(herd.asked.first, 'prompt default w1:p3: Make it like this /home/sam/inbox/from-phone-1-1-sketch.png "/home/sam/in box/from-phone-1-2-photo.jpg"');
    // None picked changes nothing.
    await tester.pump(const Duration(milliseconds: 400));
    picked = [];
    await tester.tap(find.byTooltip('Show it pictures'));
    await tester.pump();
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
    // A name on the computer has nothing in it that a path would trip over.
    expect(AgentsScreen.pictureName('My Photo (1).JPG', 1700, 0), 'from-phone-1700-1-My-Photo-1.jpg');
    expect(AgentsScreen.pictureName('../../etc/x; rm', 1700, 1), 'from-phone-1700-2.png');
    expect(AgentsScreen.pictureName('shot of api; rm -rf.png', 1700, 1), 'from-phone-1700-2-shot-of-api-rm-rf.png');
    expect(AgentsScreen.pictureName('', 1700, 2), 'from-phone-1700-3.png');
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    await tester.pump(const Duration(seconds: 5));
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
