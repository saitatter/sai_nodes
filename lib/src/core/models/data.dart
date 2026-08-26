import 'package:sai_nodes/src/core/controller/core.dart';
import 'package:sai_nodes/src/core/controller/project.dart';
import 'package:sai_nodes/src/core/events/events.dart';
import 'package:sai_nodes/src/core/helpers/single_listener_change_notifier.dart';
import 'package:sai_nodes/src/styles/styles.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

typedef LocalizedString = String Function(BuildContext context);

typedef FromTo = ({String from, String to, String fromPort, String toPort});

/// The state of a link painted on the canvas.
class LinkState {
  bool isHovered; // Not saved as it is only used during rendering
  bool isSelected; // Not saved as it is only used during rendering

  LinkState({
    this.isHovered = false,
    this.isSelected = false,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LinkState &&
          runtimeType == other.runtimeType &&
          isHovered == other.isHovered &&
          isSelected == other.isSelected;

  @override
  int get hashCode => isHovered.hashCode ^ isSelected.hashCode;
}

/// A link is a connection between two ports.
final class LinkDataModel {
  final String id;
  final FromTo fromTo;
  final LinkState state;

  LinkDataModel({
    required this.id,
    required this.fromTo,
    required this.state,
  });

  LinkDataModel copyWith({
    String? id,
    FromTo? fromTo,
    LinkState? state,
    List<Offset>? joints,
  }) {
    return LinkDataModel(
      id: id ?? this.id,
      fromTo: fromTo ?? this.fromTo,
      state: state ?? this.state,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'from': fromTo.from,
      'to': fromTo.to,
      'fromPort': fromTo.fromPort,
      'toPort': fromTo.toPort,
    };
  }

  factory LinkDataModel.fromJson(Map<String, dynamic> json) {
    return LinkDataModel(
      id: json['id'],
      fromTo: (
        from: json['from'],
        to: json['to'],
        fromPort: json['fromPort'],
        toPort: json['toPort'],
      ),
      state: LinkState(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LinkDataModel &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          fromTo == other.fromTo;

  @override
  int get hashCode => id.hashCode ^ fromTo.hashCode;
}

class TempLinkDataModel {
  final LinkStyle style;
  final Offset from;
  final Offset to;

  TempLinkDataModel({
    required this.style,
    required this.from,
    required this.to,
  });
}

enum PortDirection { input, output }

enum PortType { data, control }

/// A port prototype is the blueprint for a port instance.
///
/// It defines the name, data type, direction, and if it allows multiple links.
abstract class PortPrototype {
  final String idName;
  final LocalizedString displayName;
  final PortStyleBuilder styleBuilder;
  final Type dataType;
  final PortDirection direction;
  final PortType type;

  PortPrototype({
    required this.idName,
    required this.displayName,
    this.styleBuilder = defaultPortStyleBuilder,
    this.dataType = dynamic,
    required this.direction,
    required this.type,
  });

  bool compatibleWith(PortPrototype other);
}

class DataInputPortPrototype<T> extends PortPrototype {
  DataInputPortPrototype({
    required super.idName,
    required super.displayName,
    super.styleBuilder,
  }) : super(
          dataType: T,
          direction: PortDirection.input,
          type: PortType.data,
        );

  // called by [DataOutputPortPrototype.compatibleWith], see note there
  bool _isCompatibleWithOutput(PortPrototype other) =>
      other is DataOutputPortPrototype<T>;

  @override
  bool compatibleWith(PortPrototype other) => _isCompatibleWithOutput(other);
}

class DataOutputPortPrototype<T> extends PortPrototype {
  DataOutputPortPrototype({
    required super.idName,
    required super.displayName,
    required super.styleBuilder,
  }) : super(
          dataType: T,
          direction: PortDirection.output,
          type: PortType.data,
        );

  // the check we'd like to make here is:
  //    other is DataInputPortPrototype<U> && T is U
  //      => if [other] is an Input<Animal>, then we should be an Output<Animal/Cat/Dog/...>
  // which could also be written:
  //    DataInputPortPrototype<T> is other.runtimeType
  //    => Input<Cat> is Input<Animal>
  //
  // unfortunately dart's type/reflection system is extremely limited,
  // so you can't easily do that sort of check; instead, we (ab)use the
  // fact that /instances/ know the actual type parameter, so we ask it
  // to perform the type check for us
  @override
  bool compatibleWith(PortPrototype other) =>
      other is DataInputPortPrototype && other._isCompatibleWithOutput(this);
}

class ControlInputPortPrototype extends PortPrototype {
  ControlInputPortPrototype({
    required super.idName,
    required super.displayName,
    required super.styleBuilder,
  }) : super(direction: PortDirection.input, type: PortType.control);

  @override
  bool compatibleWith(PortPrototype other) =>
      other is ControlOutputPortPrototype;
}

class ControlOutputPortPrototype extends PortPrototype {
  ControlOutputPortPrototype({
    required super.idName,
    required super.displayName,
    required super.styleBuilder,
  }) : super(direction: PortDirection.output, type: PortType.control);

  @override
  bool compatibleWith(PortPrototype other) =>
      other is ControlInputPortPrototype;
}

/// The state of a port painted on the canvas.
class PortState with SingleListenerChangeNotifier {
  bool _isHovered;
  bool get isHovered => _isHovered;
  set isHovered(bool val) {
    if (_isHovered == val) return;
    _isHovered = val;
    notifyListeners();
  }

  PortState({
    bool isHovered = false,
  }) : _isHovered = isHovered;

  // since isHovered is only meaningful during rendering, no need to save/restore it
  factory PortState.fromJson(Map<String, dynamic> json) => PortState();
  Map<String, dynamic> toJson() => {};

  PortState copyWith({bool? isHovered}) =>
      PortState(isHovered: isHovered ?? this.isHovered);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PortState &&
          runtimeType == other.runtimeType &&
          isHovered == other.isHovered;

  @override
  int get hashCode => isHovered.hashCode;
}

/// A port is a connection point on a node.
///
/// In addition to the prototype, it holds the data, links, and offset.
final class PortDataModel {
  final PortPrototype prototype;
  dynamic data; // Not saved as it is only used during in graph execution
  Set<LinkDataModel> links = {};
  final PortState state;
  Offset offset; // Determined by Flutter
  final GlobalKey key = GlobalKey(); // Determined by Flutter

  PortDataModel({
    required this.prototype,
    required this.state,
    this.offset = Offset.zero,
  }) {
    // rebuild the cached style when the state changes
    state.listener = () => _portStyle = null;
  }

  PortStyle? _portStyle;
  PortStyle get style => _portStyle ??= prototype.styleBuilder(state);

  Map<String, dynamic> toJson() {
    return {
      'idName': prototype.idName,
      'links': links.map((link) => link.toJson()).toList(),
    };
  }

  factory PortDataModel.fromJson(
    Map<String, dynamic> json,
    Map<String, PortPrototype> portPrototypes,
  ) {
    if (!portPrototypes.containsKey(json['idName'].toString())) {
      throw Exception('Port prototype not found');
    }

    final prototype = portPrototypes[json['idName'].toString()]!;

    final instance = PortDataModel(
      prototype: prototype,
      state: PortState.fromJson(json['state'] ?? {}),
    );

    instance.links = (json['links'] as List<dynamic>)
        .map((linkJson) => LinkDataModel.fromJson(linkJson))
        .toSet();

    return instance;
  }

  PortDataModel copyWith({
    dynamic data,
    Set<LinkDataModel>? links,
    PortState? state,
    Offset? offset,
  }) {
    final instance = PortDataModel(
      prototype: prototype,
      // we can't reuse the same instance, since they should only
      // notify the new [PortInstance] object, not the old ones
      state: (state ?? this.state).copyWith(),
      offset: offset ?? this.offset,
    );

    instance.links = links ?? this.links;

    return instance;
  }
}

typedef OnVisualizerTap = Function(
  dynamic data,
  Function(dynamic data) setData,
);

typedef EditorBuilder = Widget Function(
  BuildContext context,
  Function() removeOverlay,
  dynamic data,
  Function(dynamic data, {required FieldEventType eventType}) setData,
);

/// A field prototype is the blueprint for a field instance.
///
/// It is used to store variables for use in the onExecute function of a node.
/// If explicitly allowed, the user can change the value of the field.
class FieldPrototype {
  final String idName;
  final LocalizedString displayName;
  final FieldStyle style;
  final Type dataType;
  final dynamic defaultData;
  final Widget Function(dynamic data) visualizerBuilder;
  final OnVisualizerTap? onVisualizerTap;
  final EditorBuilder? editorBuilder;

  FieldPrototype({
    required this.idName,
    required this.displayName,
    this.style = const FieldStyle.basic(),
    this.dataType = dynamic,
    this.defaultData,
    required this.visualizerBuilder,
    this.onVisualizerTap,
    this.editorBuilder,
  }) : assert(onVisualizerTap != null || editorBuilder != null);
}

/// A field is a variable that can be used in the onExecute function of a node.
///
/// In addition to the prototype, it holds the data.
class FieldDataModel {
  final FieldPrototype prototype;
  final editorOverlayController = OverlayPortalController();
  dynamic data;
  final GlobalKey key = GlobalKey(); // Determined by Flutter

  FieldDataModel({
    required this.prototype,
    required this.data,
  });

  Map<String, dynamic> toJson(Map<String, DataHandler> dataHandlers) {
    return {
      'idName': prototype.idName,
      'data': dataHandlers[prototype.dataType.toString()]?.toJson(data),
    };
  }

  factory FieldDataModel.fromJson(
    Map<String, dynamic> json,
    Map<String, FieldPrototype> fieldPrototypes,
    Map<String, DataHandler> dataHandlers,
  ) {
    if (!fieldPrototypes.containsKey(json['idName'].toString())) {
      throw Exception('Field prototype not found');
    }

    final prototype = fieldPrototypes[json['idName'].toString()]!;

    return FieldDataModel(
      prototype: prototype,
      data: json['data'] != 'null'
          ? dataHandlers[prototype.dataType.toString()]?.fromJson(json['data'])
          : null,
    );
  }

  FieldDataModel copyWith({dynamic data}) {
    return FieldDataModel(prototype: prototype, data: data ?? this.data);
  }
}

typedef OnNodeExecute = Future<void> Function(
  Map<String, dynamic> ports,
  Map<String, dynamic> fields,
  Map<String, dynamic> execState,
  Future<void> Function(Set<String>) forward,
  void Function(Set<(String, dynamic)>) put,
);

/// A node prototype is the blueprint for a node instance.
///
/// It defines the name, description, color, ports, fields, and onExecute function.
final class NodePrototype {
  final String idName;
  final LocalizedString displayName;
  final LocalizedString description;
  final NodeStyleBuilder styleBuilder;
  final NodeHeaderStyleBuilder headerStyleBuilder;
  final List<PortPrototype> ports;
  final List<FieldPrototype> fields;
  final OnNodeExecute onExecute;

  NodePrototype({
    required this.idName,
    required this.displayName,
    required this.description,
    this.styleBuilder = defaultNodeStyleBuilder,
    this.headerStyleBuilder = defaultNodeHeaderStyleBuilder,
    this.ports = const [],
    this.fields = const [],
    required this.onExecute,
  });
}

/// The state of a node widget.
final class NodeState {
  bool isSelected; // Not saved as it is only used during rendering
  bool isCollapsed;
  bool isHovered;

  NodeState({
    this.isSelected = false,
    this.isCollapsed = false,
    this.isHovered = false,
  });

  factory NodeState.fromJson(Map<String, dynamic> json) {
    return NodeState(
      isSelected: json['isSelected'],
      isCollapsed: json['isCollapsed'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'isSelected': isSelected,
      'isCollapsed': isCollapsed,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NodeState &&
          runtimeType == other.runtimeType &&
          isSelected == other.isSelected &&
          isCollapsed == other.isCollapsed;

  @override
  int get hashCode => isSelected.hashCode ^ isCollapsed.hashCode;
}

/// A node is a component in the node editor.
///
/// It holds the instances of the ports and fields, the offset, the data and the state.
final class NodeDataModel {
  final String id; // Stored to acceleate lookups

  // The resolved style for the node.
  late NodeStyle builtStyle;
  late NodeHeaderStyle builtHeaderStyle;

  final NodePrototype prototype;
  final Map<String, PortDataModel> ports;
  final Map<String, FieldDataModel> fields;
  final NodeState state;
  Offset offset; // User or system defined offset
  final GlobalKey key = GlobalKey(); // Determined by Flutter

  NodeDataModel({
    required this.id,
    required this.prototype,
    required this.ports,
    required this.fields,
    required this.state,
    this.offset = Offset.zero,
  });

  NodeDataModel copyWith({
    String? id,
    Color? color,
    Map<String, PortDataModel>? ports,
    Map<String, FieldDataModel>? fields,
    NodeState? state,
    Function(NodeDataModel node)? onRendered,
    Offset? offset,
  }) {
    return NodeDataModel(
      id: id ?? this.id,
      prototype: prototype,
      ports: ports ?? this.ports,
      state: state ?? this.state,
      fields: fields ?? this.fields,
      offset: offset ?? this.offset,
    );
  }

  Map<String, dynamic> toJson(Map<String, DataHandler> dataHandlers) {
    return {
      'id': id,
      'idName': prototype.idName,
      'ports': ports.map((k, v) => MapEntry(k, v.toJson())),
      'fields': fields.map((k, v) => MapEntry(k, v.toJson(dataHandlers))),
      'state': state.toJson(),
      'offset': [offset.dx, offset.dy],
    };
  }

  factory NodeDataModel.fromJson(
    Map<String, dynamic> json, {
    required Map<String, NodePrototype> nodePrototypes,
    required Map<String, DataHandler> dataHandlers,
  }) {
    if (!nodePrototypes.containsKey(json['idName'].toString())) {
      throw Exception('Node prototype not found');
    }

    final prototype = nodePrototypes[json['idName'].toString()]!;

    final portPrototypes = Map.fromEntries(
      prototype.ports.map(
        (prototype) => MapEntry(prototype.idName, prototype),
      ),
    );

    final ports = (json['ports'] as Map<String, dynamic>).map(
      (id, portJson) {
        return MapEntry(
          id,
          PortDataModel.fromJson(portJson, portPrototypes),
        );
      },
    );

    final fieldPrototypes = Map.fromEntries(
      prototype.fields.map(
        (prototype) => MapEntry(prototype.idName, prototype),
      ),
    );

    final fields = (json['fields'] as Map<String, dynamic>).map(
      (id, fieldJson) {
        return MapEntry(
          id,
          FieldDataModel.fromJson(fieldJson, fieldPrototypes, dataHandlers),
        );
      },
    );

    final instance = NodeDataModel(
      id: json['id'],
      prototype: prototype,
      ports: ports,
      fields: fields,
      state: NodeState(isCollapsed: json['state']['isCollapsed']),
      offset: Offset(json['offset'][0], json['offset'][1]),
    );

    return instance;
  }
}

PortDataModel createPort(String idName, PortPrototype prototype) {
  return PortDataModel(prototype: prototype, state: PortState());
}

FieldDataModel createField(String idName, FieldPrototype prototype) {
  return FieldDataModel(prototype: prototype, data: prototype.defaultData);
}

NodeDataModel createNode(
  NodePrototype prototype, {
  required NodeEditorController controller,
  required Offset offset,
}) {
  return NodeDataModel(
    id: const Uuid().v4(),
    prototype: prototype,
    ports: Map.fromEntries(
      prototype.ports.map((prototype) {
        final instance = createPort(prototype.idName, prototype);
        return MapEntry(prototype.idName, instance);
      }),
    ),
    fields: Map.fromEntries(
      prototype.fields.map((prototype) {
        final instance = createField(prototype.idName, prototype);
        return MapEntry(prototype.idName, instance);
      }),
    ),
    state: NodeState(),
    offset: offset,
  );
}

final class NodeGroup {
  final String id;
  final String name;
  final Set<String> nodeIds;

  NodeGroup({
    required this.id,
    required this.name,
    required this.nodeIds,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'nodeIds': nodeIds.toList(),
    };
  }

  factory NodeGroup.fromJson(Map<String, dynamic> json) {
    return NodeGroup(
      id: json['id'] as String,
      name: json['name'] as String,
      nodeIds: (json['nodeIds'] as List).cast<String>().toSet(),
    );
  }
}

/// A container for all the data in a project.
class NodeEditorProjectDataModel {
  Offset viewportOffset;
  double viewportZoom;
  Map<String, NodeDataModel> nodes;
  Map<String, LinkDataModel> links;

  NodeEditorProjectDataModel({
    required this.nodes,
    required this.links,
    this.viewportOffset = Offset.zero,
    this.viewportZoom = 1.0,
  });

  Map<String, dynamic> toJson(Map<String, DataHandler> dataHandlers) {
    final nodesJson =
        nodes.values.map((node) => node.toJson(dataHandlers)).toList();

    return {
      'viewport': {
        'offset': [viewportOffset.dx, viewportOffset.dy],
        'zoom': viewportZoom,
      },
      'nodes': nodesJson,
    };
  }

  factory NodeEditorProjectDataModel.fromJson(
    Map<String, dynamic> json,
    Map<String, NodePrototype> nodePrototypes,
    Map<String, DataHandler> dataHandlers,
  ) {
    final nodesJson = json['nodes'] as List<dynamic>;
    final nodes = <String, NodeDataModel>{};
    final links = <String, LinkDataModel>{};

    for (final nodeJson in nodesJson) {
      final node = NodeDataModel.fromJson(
        nodeJson,
        nodePrototypes: nodePrototypes,
        dataHandlers: dataHandlers,
      );

      for (final port in node.ports.values) {
        for (final link in port.links) {
          links[link.id] = link;
        }
      }

      nodes[node.id] = node;
    }

    return NodeEditorProjectDataModel(
      nodes: nodes,
      links: links,
      viewportOffset: Offset(
        (json['viewport']['offset'][0] as num).toDouble(),
        (json['viewport']['offset'][1] as num).toDouble(),
      ),
      viewportZoom: (json['viewport']['zoom'] as num).toDouble(),
    );
  }

  NodeEditorProjectDataModel copyWith() {
    return NodeEditorProjectDataModel(
      viewportOffset: viewportOffset,
      viewportZoom: viewportZoom,
      nodes: Map.fromEntries(
        nodes.entries.map((e) => MapEntry(e.key, e.value.copyWith())),
      ),
      links: Map.fromEntries(
        links.entries.map((e) => MapEntry(e.key, e.value)),
      ),
    );
  }
}
