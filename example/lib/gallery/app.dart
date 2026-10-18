import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sai_nodes/sai_nodes.dart';
import 'browser.dart';
import 'catalog.dart';
import 'preview.dart';
import 'session.dart';

const _background = Color(0xff101217);
const _panel = Color(0xff171a21);
const _line = Color(0xff2a2d37);
const _muted = Color(0xff969bab);
const _purple = Color(0xffb3a2ff);
const _repository = 'https://github.com/saitatter/sai_nodes';

class GalleryApp extends StatelessWidget {
  const GalleryApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'sai_nodes · The graph playground',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: _purple,
        brightness: Brightness.dark,
        surface: _panel,
      ),
      scaffoldBackgroundColor: _background,
      useMaterial3: true,
      fontFamily: 'Arial',
      dividerColor: _line,
      textTheme: ThemeData.dark().textTheme.apply(
        fontFamily: 'Arial',
        bodyColor: const Color(0xffe9eaf0),
        displayColor: const Color(0xffe9eaf0),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        isDense: true,
      ),
      tooltipTheme: const TooltipThemeData(
        waitDuration: Duration(milliseconds: 400),
      ),
    ),
    // The gallery owns category anchors. Modal routes must not replace them.
    builder: (context, child) => Navigator(
      onGenerateRoute: (settings) => MaterialPageRoute<void>(
        settings: settings,
        builder: (context) => const GalleryPage(),
      ),
    ),
  );
}

class GalleryPage extends StatefulWidget {
  const GalleryPage({super.key});
  @override
  State<GalleryPage> createState() => _GalleryPageState();
}

class _GalleryPageState extends State<GalleryPage> {
  late final Map<String, GallerySession> sessions;
  late String selected;
  final canvas = GlobalKey<NodeEditorState>();
  ConnectionRouting routing = ConnectionRouting.bezier;
  bool minimap = false;
  Size? _lastViewport;
  GallerySession get session => sessions[selected]!;
  @override
  void initState() {
    super.initState();
    sessions = {for (final demo in graphDemos) demo.id: GallerySession(demo)};
    final initial = initialDemo();
    selected = sessions.containsKey(initial) ? initial : graphDemos.first.id;
    if (selected == 'ml') routing = ConnectionRouting.orthogonal;
    session.addListener(_changed);
    _fitAfterLayout();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _fitAfterLayout() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) _fitAll();
  });
  void _fitAll() {
    final size = canvas.currentContext?.size;
    if (size == null || size.isEmpty) return;
    final scene = GraphSceneBuilder().build(session.graph);
    session.graph.focusNodes(
      scene.nodes.keys,
      scene.nodes.map((id, node) => MapEntry(id, node.geometry.bounds)),
      GraphSize(size.width, size.height),
    );
  }

  void _select(String id) {
    if (id == selected) return;
    session.stop();
    session.removeListener(_changed);
    setState(() {
      selected = id;
      routing = id == 'ml'
          ? ConnectionRouting.orthogonal
          : ConnectionRouting.bezier;
      session.addListener(_changed);
    });
    selectDemoUrl(id);
    _fitAfterLayout();
  }

  @override
  void dispose() {
    session.removeListener(_changed);
    for (final item in sessions.values) {
      item.dispose();
    }
    super.dispose();
  }

  void _notice(String text) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
  );

  Future<GraphNode?> _pick(GraphNodePickerRequest request) async {
    final choice = await showDialog<DemoNode>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Add a node'),
        children: [
          for (final spec in session.demo.nodes)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, spec),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Icon(
                      session.demo.icon,
                      color: session.demo.color,
                      size: 20,
                    ),
                    const SizedBox(width: 16),
                    Text(spec.title),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
    return choice == null
        ? null
        : GraphNode(
            id: newGraphId(),
            type: choice.type(selected),
            data: choice.defaults,
          );
  }

  Future<void> _add() async {
    final target = session;
    final node = await _pick(GraphNodePickerRequest(position: GraphPoint.zero));
    if (!mounted || target != session || node == null) return;
    final world = session.graph.camera.viewportToWorld(
      const GraphPoint(220, 180),
    );
    session.graph.execute(
      AddNodeCommand(
        gallerySpace,
        node,
        presentation: NodePresentation(nodeId: node.id, position: world),
      ),
    );
    session.graph.select(GraphSelection(nodes: {node.id}));
  }

  Future<void> _source() async {
    final target = session;
    final source = const JsonEncoder.withIndent(
      '  ',
    ).convert(target.graph.document.toJson());
    final edited = await showDialog<String>(
      context: context,
      builder: (context) => _JsonDialog(
        title: 'Graph source',
        source: source,
        validate: (text) {
          // Validate against a disposable controller; malformed imports cannot mutate the open graph.
          final validation = GallerySession(target.demo);
          try {
            validation.loadJson(text);
          } finally {
            validation.dispose();
          }
        },
      ),
    );
    if (!mounted || target != session || edited == null) return;
    target.loadJson(edited);
    _fitAfterLayout();
  }

  Future<void> _jsonField(GraphNode node, DemoField field) async {
    final target = session;
    final edited = await showDialog<String>(
      context: context,
      builder: (context) => _JsonDialog(
        title: field.label,
        source: const JsonEncoder.withIndent('  ').convert(node.data[field.id]),
        validate: (text) {
          if (jsonDecode(text) is! List) {
            throw const FormatException('Expected a JSON array.');
          }
        },
      ),
    );
    if (!mounted || target != session || edited == null) return;
    target.update(node, field, jsonDecode(edited) as List);
  }

  Widget _link(String text, String url, {bool icon = false}) => TextButton(
    onPressed: () => openGalleryLink(url),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: _muted, fontSize: 12),
          ),
        ),
        if (icon) ...[
          const SizedBox(width: 6),
          const Icon(Icons.north_east, size: 13, color: _muted),
        ],
      ],
    ),
  );

  Widget _brand() => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 31,
        height: 31,
        decoration: BoxDecoration(
          color: _purple.withValues(alpha: .13),
          border: Border.all(color: _purple.withValues(alpha: .35)),
          borderRadius: BorderRadius.circular(9),
        ),
        child: const Icon(Icons.polyline_rounded, size: 19, color: _purple),
      ),
      const SizedBox(width: 10),
      const Text(
        'sai',
        style: TextStyle(
          fontSize: 21,
          fontWeight: FontWeight.w700,
          letterSpacing: -.7,
        ),
      ),
      const Text(
        '_nodes',
        style: TextStyle(fontSize: 21, color: _muted, letterSpacing: -.7),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      if (_lastViewport != bounds.biggest) {
        _lastViewport = bounds.biggest;
        _fitAfterLayout();
      }
      final wide = bounds.maxWidth >= 1180,
          sidebar = bounds.maxWidth >= 1000,
          small = bounds.maxWidth < 650;
      return Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Container(
                height: 66,
                padding: EdgeInsets.symmetric(horizontal: small ? 16 : 28),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: _line)),
                ),
                child: Row(
                  children: [
                    _brand(),
                    if (!small) ...[
                      const SizedBox(width: 20),
                      _pill('1.0.0', _purple),
                      const SizedBox(width: 20),
                      const Text(
                        'THE GRAPH PLAYGROUND',
                        style: TextStyle(
                          color: _muted,
                          fontSize: 10,
                          letterSpacing: 1.6,
                        ),
                      ),
                    ],
                    const Spacer(),
                    if (!small)
                      _link(
                        'Documentation',
                        '$_repository/blob/main/docs/api.md',
                      ),
                    _link('GitHub', _repository, icon: true),
                  ],
                ),
              ),
              Expanded(
                child: Row(
                  children: [
                    if (sidebar) _sidebar(),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: EdgeInsets.fromLTRB(
                              small ? 16 : 28,
                              small ? 15 : 25,
                              small ? 16 : 28,
                              small ? 12 : 22,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      '0${graphDemos.indexOf(session.demo) + 1} / EXPLORE THE POSSIBILITIES',
                                      style: TextStyle(
                                        color: session.demo.color,
                                        fontSize: 10,
                                        letterSpacing: 1.3,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const Spacer(),
                                    if (!small)
                                      const Text(
                                        'Flutter + Dart · open source',
                                        style: TextStyle(
                                          color: _muted,
                                          fontSize: 11,
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  session.demo.title,
                                  style: TextStyle(
                                    fontSize: small ? 25 : 34,
                                    letterSpacing: -.9,
                                    fontWeight: FontWeight.w600,
                                    height: 1.15,
                                  ),
                                ),
                                if (!small) ...[
                                  const SizedBox(height: 10),
                                  Text(
                                    session.demo.description,
                                    style: const TextStyle(
                                      color: _muted,
                                      fontSize: 13,
                                      height: 1.5,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (!sidebar)
                            Padding(
                              padding: EdgeInsets.fromLTRB(
                                small ? 16 : 28,
                                0,
                                small ? 16 : 28,
                                12,
                              ),
                              child: DropdownButtonFormField<String>(
                                key: const ValueKey('example-selector'),
                                initialValue: selected,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: 'Explore an example',
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 10,
                                  ),
                                ),
                                items: [
                                  for (final demo in graphDemos)
                                    DropdownMenuItem(
                                      value: demo.id,
                                      child: Text(
                                        demo.category,
                                        style: const TextStyle(fontSize: 13),
                                      ),
                                    ),
                                ],
                                onChanged: (value) {
                                  if (value != null) _select(value);
                                },
                              ),
                            ),
                          Expanded(
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(
                                small ? 10 : 24,
                                0,
                                small ? 10 : 24,
                                small ? 10 : 18,
                              ),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  border: Border.all(color: _line),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(13),
                                  child: Column(
                                    children: [
                                      _toolbar(wide: wide, small: small),
                                      Expanded(
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Stack(
                                                children: [
                                                  Positioned.fill(
                                                    child: NodeEditor(
                                                      key: canvas,
                                                      controller: session.graph,
                                                      executionSource:
                                                          session.visuals,
                                                      onCreateNode: _pick,
                                                      onError: _notice,
                                                      routing: routing,
                                                      showMinimap: minimap,
                                                      fieldBuilder:
                                                          (
                                                            context,
                                                            model,
                                                            field,
                                                            value,
                                                            onChanged,
                                                          ) => Row(
                                                            children: [
                                                              Expanded(
                                                                child: Text(
                                                                  field.label,
                                                                  maxLines: 1,
                                                                  overflow:
                                                                      TextOverflow
                                                                          .ellipsis,
                                                                  style: const TextStyle(
                                                                    color:
                                                                        _muted,
                                                                    fontSize:
                                                                        11,
                                                                  ),
                                                                ),
                                                              ),
                                                              const SizedBox(
                                                                width: 8,
                                                              ),
                                                              Flexible(
                                                                child: Text(
                                                                  value is List
                                                                      ? jsonEncode(
                                                                          value,
                                                                        )
                                                                      : '$value',
                                                                  maxLines: 1,
                                                                  overflow:
                                                                      TextOverflow
                                                                          .ellipsis,
                                                                  style: TextStyle(
                                                                    color: session
                                                                        .demo
                                                                        .color,
                                                                    fontSize:
                                                                        11,
                                                                  ),
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                      theme:
                                                          const GraphEditorTheme(
                                                            background: Color(
                                                              0xff13161d,
                                                            ),
                                                            grid: Color(
                                                              0xff2d3040,
                                                            ),
                                                            node: Color(
                                                              0xff202430,
                                                            ),
                                                            border: Color(
                                                              0xff3c4253,
                                                            ),
                                                            selected: _purple,
                                                            cornerRadius: 10,
                                                          ),
                                                      headerBuilder: (context, model) => Row(
                                                        children: [
                                                          Icon(
                                                            session.demo.icon,
                                                            size: 15,
                                                            color: session
                                                                .demo
                                                                .color,
                                                          ),
                                                          const SizedBox(
                                                            width: 8,
                                                          ),
                                                          Expanded(
                                                            child: Text(
                                                              model.label,
                                                              maxLines: 1,
                                                              overflow:
                                                                  TextOverflow
                                                                      .ellipsis,
                                                              style: const TextStyle(
                                                                fontSize: 12,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                  Positioned(
                                                    left: 14,
                                                    bottom: 12,
                                                    child: IgnorePointer(
                                                      child: Container(
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              horizontal: 10,
                                                              vertical: 7,
                                                            ),
                                                        decoration: BoxDecoration(
                                                          color: _background
                                                              .withValues(
                                                                alpha: .9,
                                                              ),
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                7,
                                                              ),
                                                        ),
                                                        child: Text(
                                                          small
                                                              ? 'Pinch to zoom · drag to explore'
                                                              : 'Drag nodes · connect ports · scroll to zoom · right-click for more',
                                                          style:
                                                              const TextStyle(
                                                                fontSize: 10,
                                                                color: _muted,
                                                              ),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            if (wide)
                                              Container(
                                                width: 300,
                                                decoration: const BoxDecoration(
                                                  color: _panel,
                                                  border: Border(
                                                    left: BorderSide(
                                                      color: _line,
                                                    ),
                                                  ),
                                                ),
                                                child: _inspector(),
                                              ),
                                          ],
                                        ),
                                      ),
                                      _status(small),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (!small)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(28, 0, 28, 13),
                              child: Row(
                                children: [
                                  const Expanded(
                                    child: Text(
                                      'One canvas. Seven starting points. Yours to build on.',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: _muted,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                  _link(
                                    'Package on pub.dev',
                                    'https://pub.dev/packages/sai_nodes',
                                    icon: true,
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );

  Widget _pill(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .09),
      border: Border.all(color: color.withValues(alpha: .2)),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      text,
      style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w500),
    ),
  );

  Widget _sidebar() => Container(
    width: 224,
    decoration: const BoxDecoration(
      border: Border(right: BorderSide(color: _line)),
    ),
    padding: const EdgeInsets.fromLTRB(16, 28, 16, 16),
    child: ListView(
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 10, bottom: 18),
          child: Text(
            'EXAMPLE COLLECTION',
            style: TextStyle(color: _muted, fontSize: 10, letterSpacing: 1.4),
          ),
        ),
        for (final demo in graphDemos)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Material(
              color: selected == demo.id
                  ? demo.color.withValues(alpha: .1)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                key: ValueKey('demo-${demo.id}'),
                borderRadius: BorderRadius.circular(10),
                onTap: () => _select(demo.id),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 16,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        demo.icon,
                        size: 19,
                        color: selected == demo.id ? demo.color : _muted,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          demo.category,
                          style: TextStyle(
                            fontSize: 12,
                            color: selected == demo.id
                                ? demo.color
                                : const Color(0xffb9becb),
                            fontWeight: selected == demo.id
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                      if (selected == demo.id)
                        Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            color: demo.color,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: _panel,
            border: Border.all(color: _line),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.code_rounded, color: _purple, size: 21),
              const SizedBox(height: 10),
              const Text(
                'Your logic. Our canvas.',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 7),
              const Text(
                'Typed connections, undo history, and a canvas that gets out of your way.',
                style: TextStyle(color: _muted, fontSize: 11, height: 1.6),
              ),
              const SizedBox(height: 8),
              _link('Start building', '$_repository#development', icon: true),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _toolbar({required bool wide, required bool small}) => Container(
    height: small ? 52 : 57,
    padding: const EdgeInsets.symmetric(horizontal: 10),
    decoration: const BoxDecoration(
      color: _panel,
      border: Border(bottom: BorderSide(color: _line)),
    ),
    child: Row(
      children: [
        if (!small) ...[
          _pill('LIVE EDITOR', session.demo.color),
          const SizedBox(width: 9),
        ],
        IconButton(
          tooltip: 'Add node',
          onPressed: _add,
          icon: const Icon(Icons.add, size: 19),
          visualDensity: VisualDensity.compact,
        ),
        IconButton(
          tooltip: 'Undo',
          onPressed: session.graph.canUndo ? session.graph.undo : null,
          icon: const Icon(Icons.undo_rounded, size: 18),
          visualDensity: VisualDensity.compact,
        ),
        if (!small)
          IconButton(
            tooltip: 'Redo',
            onPressed: session.graph.canRedo ? session.graph.redo : null,
            icon: const Icon(Icons.redo_rounded, size: 18),
            visualDensity: VisualDensity.compact,
          ),
        IconButton(
          tooltip: 'Fit graph',
          onPressed: _fitAll,
          icon: const Icon(Icons.fit_screen_rounded, size: 19),
          visualDensity: VisualDensity.compact,
        ),
        if (!small)
          PopupMenuButton<ConnectionRouting>(
            tooltip: 'Connection style',
            icon: const Icon(Icons.route_outlined, size: 18),
            initialValue: routing,
            onSelected: (value) => setState(() => routing = value),
            itemBuilder: (context) => [
              for (final item in ConnectionRouting.values)
                PopupMenuItem(value: item, child: Text(item.name)),
            ],
          ),
        const Spacer(),
        if (!wide)
          IconButton(
            tooltip: 'Preview and properties',
            onPressed: _showInspector,
            icon: const Icon(Icons.tune_rounded, size: 19),
            visualDensity: VisualDensity.compact,
          ),
        if (!small)
          TextButton(
            onPressed: _source,
            child: const Text('Source', style: TextStyle(fontSize: 12)),
          ),
        PopupMenuButton<String>(
          tooltip: 'More actions',
          onSelected: (action) {
            if (action == 'reset') {
              session.reset();
              _fitAfterLayout();
            } else if (action == 'source') {
              unawaited(_source());
            } else {
              setState(() => minimap = !minimap);
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(value: 'reset', child: Text('Reset example')),
            const PopupMenuItem(value: 'source', child: Text('Graph JSON')),
            PopupMenuItem(
              value: 'minimap',
              child: Text(minimap ? 'Hide minimap' : 'Show minimap'),
            ),
          ],
          icon: const Icon(Icons.more_horiz, size: 20),
        ),
        const SizedBox(width: 6),
        FilledButton.icon(
          key: const ValueKey('run-demo'),
          onPressed: session.running
              ? () {
                  setState(() => session.stop());
                }
              : () => unawaited(session.run(audio: selected == 'audio')),
          style: FilledButton.styleFrom(
            backgroundColor: session.demo.color,
            foregroundColor: _background,
            padding: EdgeInsets.symmetric(horizontal: small ? 10 : 16),
            minimumSize: const Size(0, 34),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(7),
            ),
          ),
          icon: Icon(
            session.running ? Icons.stop_rounded : Icons.play_arrow_rounded,
            size: 17,
          ),
          label: Text(
            session.running
                ? 'Stop'
                : selected == 'audio'
                ? 'Play patch'
                : 'Run',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );

  Widget _status(bool small) => Container(
    height: 33,
    padding: const EdgeInsets.symmetric(horizontal: 13),
    decoration: const BoxDecoration(
      color: _panel,
      border: Border(top: BorderSide(color: _line)),
    ),
    child: Row(
      children: [
        Container(
          width: 5,
          height: 5,
          decoration: BoxDecoration(
            color: session.error != null
                ? Colors.redAccent
                : const Color(0xff6fd9ba),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            session.error != null
                ? 'Run needs attention · open preview'
                : session.running
                ? 'Following the connected graph…'
                : session.result == null
                ? 'Graph changed · run to refresh'
                : 'Ready · ${session.result!.visited.length} nodes evaluated locally',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: _muted, fontSize: 10),
          ),
        ),
        if (!small)
          Text(
            '${session.graph.activeSpace!.nodes.length} nodes  /  ${session.graph.activeSpace!.connections.length} edges',
            style: const TextStyle(color: _muted, fontSize: 10),
          ),
      ],
    ),
  );

  void _showInspector() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * .78,
        child: AnimatedBuilder(
          animation: session,
          builder: (context, _) => _inspector(),
        ),
      ),
    );
  }

  Widget _inspector() {
    final graph = session.graph;
    final nodeId = graph.selection.nodes.firstOrNull;
    final node = nodeId == null ? null : graph.activeSpace!.nodes[nodeId];
    final spec = node == null ? null : session.demo.specFor(node);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            const Text(
              'PREVIEW',
              style: TextStyle(fontSize: 10, color: _muted, letterSpacing: 1.4),
            ),
            const Spacer(),
            _pill('LOCAL', const Color(0xff6fd9ba)),
          ],
        ),
        const SizedBox(height: 18),
        DemoPreview(session: session),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 22),
          child: Divider(height: 1, color: _line),
        ),
        const Text(
          'NODE PROPERTIES',
          style: TextStyle(fontSize: 10, color: _muted, letterSpacing: 1.4),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: ValueKey('node-picker-$selected-$nodeId'),
          initialValue: nodeId,
          isExpanded: true,
          hint: const Text('Select a node', style: TextStyle(fontSize: 12)),
          decoration: const InputDecoration(
            contentPadding: EdgeInsets.symmetric(horizontal: 11, vertical: 13),
          ),
          items: [
            for (final item in graph.activeSpace!.nodes.values)
              DropdownMenuItem(
                value: item.id,
                child: Text(
                  session.demo.specFor(item).title,
                  style: const TextStyle(fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (value) {
            if (value != null) graph.select(GraphSelection(nodes: {value}));
          },
        ),
        const SizedBox(height: 16),
        if (node == null)
          Text(
            session.demo.hint,
            style: const TextStyle(color: _muted, fontSize: 12, height: 1.7),
          ),
        if (node != null && spec!.fields.isEmpty)
          const Text(
            'This node uses its connected inputs. Rewire a port to change what flows through it.',
            style: TextStyle(color: _muted, fontSize: 12, height: 1.6),
          ),
        if (node != null)
          for (final field in spec!.fields) ...[
            _field(node, field),
            const SizedBox(height: 18),
          ],
        if (node != null)
          TextButton.icon(
            onPressed: () => graph.deleteSelection(),
            icon: const Icon(Icons.delete_outline, size: 16),
            label: const Text(
              'Delete selected',
              style: TextStyle(fontSize: 12),
            ),
          ),
        const SizedBox(height: 20),
        const Text(
          'sai_nodes edits the graph.\nThis example host runs the logic.',
          style: TextStyle(color: _muted, fontSize: 10, height: 1.6),
        ),
      ],
    );
  }

  Widget _field(GraphNode node, DemoField field) {
    final value = node.data[field.id] ?? field.value;
    final key = ValueKey('field-${node.id}-${field.id}');
    if (field.kind == GraphFieldKind.boolean) {
      return Material(
        color: Colors.transparent,
        child: SwitchListTile.adaptive(
          key: key,
          contentPadding: EdgeInsets.zero,
          title: Text(field.label, style: const TextStyle(fontSize: 12)),
          value: value == true,
          activeThumbColor: session.demo.color,
          onChanged: (value) => session.update(node, field, value),
        ),
      );
    }
    if (field.kind == GraphFieldKind.number) {
      final number = value is num ? value.toDouble() : field.min;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(field.label, style: const TextStyle(fontSize: 12)),
              ),
              Text(
                number.toStringAsFixed(field.max <= 1 ? 2 : 1),
                style: TextStyle(color: session.demo.color, fontSize: 12),
              ),
            ],
          ),
          Slider(
            key: key,
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 12),
            min: field.min,
            max: field.max,
            value: number.clamp(field.min, field.max),
            activeColor: session.demo.color,
            onChanged: (value) => session.update(node, field, value),
          ),
        ],
      );
    }
    if (field.kind == GraphFieldKind.choice) {
      return DropdownButtonFormField<String>(
        key: ValueKey('$key-$value'),
        initialValue: field.choices.contains(value)
            ? value as String
            : field.choices.first,
        decoration: InputDecoration(labelText: field.label),
        items: [
          for (final choice in field.choices)
            DropdownMenuItem(value: choice, child: Text(choice)),
        ],
        onChanged: (value) {
          if (value != null) session.update(node, field, value);
        },
      );
    }
    if (field.kind == GraphFieldKind.json) {
      return OutlinedButton.icon(
        key: key,
        onPressed: () => _jsonField(node, field),
        icon: const Icon(Icons.data_object, size: 16),
        label: Text(
          'Edit ${field.label.toLowerCase()}',
          style: const TextStyle(fontSize: 11),
        ),
      );
    }
    return TextFormField(
      key: ValueKey('$key-$value'),
      initialValue: '$value',
      decoration: InputDecoration(
        labelText: field.label,
        helperText: 'Press Enter to apply',
      ),
      style: const TextStyle(fontSize: 12),
      onFieldSubmitted: (value) => session.update(node, field, value),
    );
  }
}

class _JsonDialog extends StatefulWidget {
  const _JsonDialog({
    required this.title,
    required this.source,
    required this.validate,
  });
  final String title, source;
  final void Function(String) validate;
  @override
  State<_JsonDialog> createState() => _JsonDialogState();
}

class _JsonDialogState extends State<_JsonDialog> {
  late final text = TextEditingController(text: widget.source);
  String? error;
  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 720,
      height: MediaQuery.sizeOf(context).height * .55,
      child: TextField(
        key: const ValueKey('json-editor'),
        controller: text,
        maxLines: null,
        expands: true,
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 11,
          height: 1.5,
        ),
        decoration: InputDecoration(errorText: error, alignLabelWithHint: true),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () {
          unawaited(Clipboard.setData(ClipboardData(text: text.text)));
        },
        child: const Text('Copy'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          try {
            widget.validate(text.text);
            Navigator.pop(context, text.text);
          } catch (problem) {
            setState(
              () => error = problem.toString().replaceFirst(
                'FormatException: ',
                '',
              ),
            );
          }
        },
        child: const Text('Apply'),
      ),
    ],
  );
}
