import 'dart:async';

import 'package:sai_nodes/src/core/controller/callback.dart';
import 'package:sai_nodes/src/core/events/events.dart';
import 'package:sai_nodes/src/core/localization/delegate.dart';
import 'package:flutter/material.dart';

import '../models/data.dart';
import 'core.dart';

/// A class that manages the execution of the node editor graph.
///
/// NOTE: This class is still in development and there are performance improvements to be made.
class NodeEditorExecutionHelper {
  final NodeEditorController controller;

  final Set<String> _executedNodes = {};
  final Map<String, Map<String, dynamic>> _execState = {};
  final Map<String, Set<String>> _dataDeps = {};

  Timer? _buildGraphDelayTimer;
  Timer? _runGraphDelayTimer;

  NodeEditorProjectDataModel projectData = NodeEditorProjectDataModel(
    nodes: {},
    links: {},
  );

  Map<String, NodeDataModel> get nodes => projectData.nodes;

  NodeEditorExecutionHelper(this.controller) {
    controller.eventBus.events.listen(_handleRunnerEvents);
  }

  void clear() {
    projectData = NodeEditorProjectDataModel(
      nodes: {},
      links: {},
    );

    _execState.clear();
    _executedNodes.clear();
    _dataDeps.clear();
  }

  /// Handles events from the controller and updates the graph accordingly.
  void _handleRunnerEvents(NodeEditorEvent event) {
    if (event is LoadProjectEvent || event is NewProjectEvent) {
      _buildGraphDelayTimer?.cancel();
      _runGraphDelayTimer?.cancel();

      if (controller.config.autoBuildGraph) {
        _buildDepsMap();

        if (controller.config.autoRunGraph) {
          executeGraph();
        }
      }
    }

    if (event is AddNodeEvent ||
        event is RemoveNodeEvent ||
        event is AddLinkEvent ||
        event is RemoveLinkEvent ||
        (event is NodeFieldEvent &&
            event.eventType == FieldEventType.submit)) {
      if (controller.config.autoBuildGraph) {
        _buildGraphDelayTimer?.cancel();
        _buildGraphDelayTimer =
            Timer(controller.config.autoBuildGraphDelay, () {
          _buildDepsMap();

          if (controller.config.autoRunGraph) {
            _runGraphDelayTimer?.cancel();
            _runGraphDelayTimer =
                Timer(controller.config.autoRunGraphDelay, () {
              executeGraph();
            });
          }
        });
      }
    }
  }

  /// Builds the data dependency map.
  ///
  /// The data dependency map is a map of node IDs to the unique IDs of nodes connected to the node's data input ports.
  /// This map is used to determine the order in which nodes are executed to ensure that data is propagated correctly.
  void _buildDepsMap() {
    _dataDeps.clear();

    projectData = controller.project.projectData.copyWith();

    final Set<String> visited = {};

    for (final node in projectData.nodes.values) {
      if (!node.ports.values.every(
        (port) => port.prototype.direction == PortDirection.output,
      )) {
        continue;
      }

      _findDeps(node.id, visited);
    }
  }

  void _findDeps(String nodeId, Set<String> visited) {
    if (visited.contains(nodeId)) return;

    visited.add(nodeId);

    _dataDeps[nodeId] = _getConnectedNodeIdsFromNode(
      nodes[nodeId]!,
      PortDirection.input,
      PortType.data,
    );

    final connectedOutputNodeIds = _getConnectedNodeIdsFromNode(
      nodes[nodeId]!,
      PortDirection.output,
      PortType.control,
    );

    for (final connectedNodeId in connectedOutputNodeIds) {
      _findDeps(connectedNodeId, visited);
    }
  }

  // Returns the unique IDs of nodes connected to a given port.
  Set<String> _getConnectedNodeIdsFromPort(PortDataModel port) {
    final connectedNodeIds = <String>{};

    for (final link in port.links) {
      final connectedNode = nodes[
          port.prototype.direction == PortDirection.input
              ? link.fromTo.from
              : link.fromTo.fromPort]!;
      connectedNodeIds.add(connectedNode.id);
    }

    return connectedNodeIds;
  }

  /// Returns the unique IDs of nodes connected to a given node's input or output ports.
  Set<String> _getConnectedNodeIdsFromNode(
    NodeDataModel node,
    PortDirection direction,
    PortType type,
  ) {
    final connectedNodeIds = <String>{};

    final ports = node.ports.values.where(
      (port) =>
          port.prototype.direction == direction && port.prototype.type == type,
    );

    for (final port in ports) {
      connectedNodeIds.addAll(_getConnectedNodeIdsFromPort(port));
    }

    return connectedNodeIds;
  }

  /// Executes the entire graph asynchronously
  Future<void> executeGraph({BuildContext? context}) async {
    if (_runGraphDelayTimer != null && _runGraphDelayTimer!.isActive) {
      _runGraphDelayTimer!.cancel();
    }

    if (controller.config.autoBuildGraph) {
      if (_buildGraphDelayTimer != null && _buildGraphDelayTimer!.isActive) {
        _buildGraphDelayTimer!.cancel();
        _buildDepsMap();
      }
    } else {
      _buildDepsMap();
    }

    _executedNodes.clear();
    _execState.clear();

    for (final node in nodes.values) {
      if (!node.ports.values.every(
        (port) => port.prototype.direction == PortDirection.output,
      )) {
        continue;
      }

      await _executeNode(node, context: context);
    }
  }

  /// Executes a node asynchronously
  ///
  /// This method is responsible for executing a node and propagating accordingly
  /// with the data dependecy map. It provides the onExecute callback with the
  /// necessary context information and callbacks to forward events and put data.
  /// The method also handles errors and displays them in the node editor.
  Future<void> _executeNode(
    NodeDataModel node, {
    BuildContext? context,
  }) async {
    final strings = NodeEditorLocalizations.of(context);

    /// A function that forwards events to connected nodes through control ports.
    ///
    /// The function takes a [Set] of unique IDs of the ports to forward events to and
    /// returns a [Future] that completes when all connected nodes have been executed
    Future<void> forward(Set<String> portIdNames) async {
      final futures = <Future<void>>[];

      for (final portIdName in portIdNames) {
        final port = node.ports[portIdName]!;

        final connectedNodeIds = _getConnectedNodeIdsFromPort(
          port,
        );

        if (port.prototype.type != PortType.control) {
          throw Exception('Port ${port.prototype.idName} is not of type event');
        }

        for (final nodeId in connectedNodeIds) {
          futures.add(_executeNode(nodes[nodeId]!));
        }
      }

      await Future.wait(futures);
    }

    /// A function that puts data into connected nodes through data ports.
    ///
    /// The function takes a [Set] of records containing the unique ID of the port and the data to be put into the port.
    void put(Set<(String, dynamic)> idNamesAndData) {
      for (final idNameAndData in idNamesAndData) {
        final (idName, data) = idNameAndData;

        final port = node.ports[idName]!;
        port.data = data;

        if (port.prototype.type != PortType.data) {
          throw Exception('Port ${port.prototype.idName} is not of type data');
        }

        for (final link in port.links) {
          final connectedNode = nodes[link.fromTo.fromPort]!;
          final connectedPort = connectedNode.ports[link.fromTo.toPort]!;

          connectedPort.data = data;
        }
      }
    }

    _executedNodes.add(node.id);

    for (final dep in _dataDeps[node.id]!) {
      if (_executedNodes.contains(dep)) continue;
      await _executeNode(nodes[dep]!);
    }

    try {
      await node.prototype.onExecute(
        node.ports.map((portId, port) => MapEntry(portId, port.data)),
        node.fields.map((fieldId, field) => MapEntry(fieldId, field.data)),
        _execState.putIfAbsent(node.id, () => {}),
        forward,
        put,
      );
    } catch (e) {
      controller.focusNodesById({node.id});
      controller.onCallback?.call(
        CallbackType.error,
        strings.failedToExecuteNodeErrorMsg(e.toString()),
      );
      return;
    }

    _execState.remove(node.id);
  }
}
