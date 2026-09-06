import 'dart:convert';

import 'package:sai_nodes/src/core/controller/callback.dart';
import 'package:sai_nodes/src/core/localization/delegate.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../events/bus.dart';
import '../events/events.dart';
import '../models/data.dart';
import '../utils/misc/json_extensions.dart';
import '../utils/rendering/renderbox.dart';
import 'core.dart';
import 'utils.dart';

/// Encodes host-owned, JSON-compatible data alongside a node clipboard
/// payload. The package still owns node and link serialization.
typedef NodeEditorClipboardPayloadEncoder =
    Map<String, dynamic>? Function(Iterable<NodeDataModel> nodes);

/// Restores host-owned clipboard data after the package has created the pasted
/// node instances with their new IDs.
typedef NodeEditorClipboardPayloadDecoder = void Function(
  Map<String, dynamic> data,
  Iterable<NodeDataModel> pastedNodes,
);

/// A class that manages the clipboard operations of the node editor.
///
/// The clipboard operations include copying, pasting, and cutting nodes.
class NodeEditorClipboardHelper {
  final NodeEditorController controller;

  NodeEditorEventBus get eventBus => controller.eventBus;
  Offset get viewportOffset => controller.viewportOffset;
  double get viewportZoom => controller.viewportZoom;
  GlobalKey get editorKey => controller.editorKey;
  Map<String, NodePrototype> get nodePrototypes => controller.nodePrototypes;
  Map<String, NodeDataModel> get nodes => controller.nodes;
  Set<String> get selectedNodeIds => controller.selectedNodeIds;

  NodeEditorClipboardHelper(
    this.controller, {
    this.payloadEncoder,
    this.payloadDecoder,
  });

  final NodeEditorClipboardPayloadEncoder? payloadEncoder;
  final NodeEditorClipboardPayloadDecoder? payloadDecoder;

  /// Copies the selected nodes to the clipboard.
  ///
  /// The copied nodes are deep copied to avoid altering the original nodes in the
  /// copyWith operations to reset the state of the nodes. The copied nodes are encoded
  /// to JSON and then encoded to base64 (to avoid direct tampering with the JSON data)
  /// and then copied to the clipboard.
  Future<String> copySelection({BuildContext? context}) async {
    final strings = NodeEditorLocalizations.of(context);

    if (selectedNodeIds.isEmpty) return '';

    final encompassingRect =
        NodeEditorUtils.calculateEncompassingRect(selectedNodeIds, nodes);

    final selectedNodes = selectedNodeIds.map((id) {
      final nodeCopy = nodes[id]!.copyWith();

      final relativeOffset = nodeCopy.offset - encompassingRect.topLeft;

      // We make deep copies as we only want to copy the links that are within the selection.
      final updatedPorts = nodeCopy.ports.map((portId, port) {
        final deepCopiedLinks = port.links.where((link) {
          return selectedNodeIds.contains(link.endpoints.sourceNodeId) &&
              selectedNodeIds.contains(link.endpoints.targetNodeId);
        }).toSet();

        return MapEntry(
          portId,
          port.copyWith(links: deepCopiedLinks),
        );
      });

      // Update the node with deep copied ports, state, and relative offset
      return nodeCopy.copyWith(
        offset: relativeOffset,
        state: NodeState(),
        ports: updatedPorts,
      );
    }).toList();

    late final String base64Data;

    try {
      final selectedNodesJson = selectedNodes
          .map((node) => node.toJson(controller.project.dataHandlers))
          .toList();

      final nodesJsonData = jsonEncode(selectedNodesJson);
      final encompassingRectJsonData = jsonEncode(encompassingRect.toJson());

      final jsonData = jsonEncode({
        'nodes': nodesJsonData,
        'encompassingRect': encompassingRectJsonData,
        if (payloadEncoder != null) 'extension': payloadEncoder!(selectedNodes),
      });

      base64Data = base64Encode(utf8.encode(jsonData));
    } catch (e) {
      controller.onCallback?.call(
        CallbackType.error,
        strings.failedToCopySelectionErrorMsg(e.toString()),
      );
      return '';
    }

    await Clipboard.setData(ClipboardData(text: base64Data));

    controller.onCallback?.call(
      CallbackType.success,
      strings.selectionCopiedSuccessfullyMsg,
    );

    eventBus.emit(
      CopySelectionEvent(
        id: const Uuid().v4(),
        base64Data,
      ),
    );

    return base64Data;
  }

  /// Pastes the nodes from the clipboard to the node editor.
  ///
  /// The clipboard data is decoded from base64 and then decoded from JSON.
  /// The JSON data is then used to create instances of the nodes. All entities
  /// are then mapped to new IDs to avoid conflicts with existing nodes.
  /// The nodes are then deep copied with the new IDs and added to the node editor.
  ///
  /// See [mapToNewIds] for more info on how the new IDs are generated.
  Future<void> pasteSelection({
    Offset? position,
    BuildContext? context,
    String? clipboardContent,
  }) async {
    final strings = NodeEditorLocalizations.of(context);

    final clipboardText =
        clipboardContent ?? (await Clipboard.getData('text/plain'))?.text;
    if (clipboardText == null || clipboardText.isEmpty) return;

    late List<dynamic> nodesJson;
    late Rect encompassingRect;
    Map<String, dynamic>? extensionData;

    try {
      final base64Data = utf8.decode(base64Decode(clipboardText));
      final jsonData = jsonDecode(base64Data) as Map<String, dynamic>;

      nodesJson = jsonDecode(jsonData['nodes']) as List<dynamic>;
      encompassingRect = JSONRect.fromJson(
        jsonDecode(jsonData['encompassingRect']),
      );
      final extension = jsonData['extension'];
      if (extension is Map) {
        extensionData = Map<String, dynamic>.from(extension);
      }
    } catch (e) {
      controller.onCallback?.call(
        CallbackType.error,
        strings.failedToPasteSelectionErrorMsg(e.toString()),
      );
      return;
    }

    if (position == null) {
      final viewportSize = RenderBoxUtils.getSizeFromGlobalKey(editorKey)!;

      position = Rect.fromLTWH(
        -viewportOffset.dx -
            (viewportSize.width / 2) -
            (encompassingRect.width / 2),
        -viewportOffset.dy -
            (viewportSize.height / 2) -
            (encompassingRect.height / 2),
        viewportSize.width,
        viewportSize.height,
      ).center;
    }

    // Create instances from the JSON data.
    final instances = nodesJson.map((node) {
      return NodeDataModel.fromJson(
        node,
        nodePrototypes: controller.nodePrototypes,
        dataHandlers: controller.project.dataHandlers,
      );
    }).toList();

    // Called on each paste, see [NodeEditorController._mapToNewIds] for more info.
    final newIds = await NodeEditorUtils.mapToNewIds(instances);

    final deepCopiedNodes = instances.map((instance) {
      return instance.copyWith(
        id: newIds[instance.id],
        offset: instance.offset + position!,
        fields: instance.fields,
        ports: instance.ports.map((key, port) {
          return MapEntry(
            port.prototype.idName,
            port.copyWith(
              links: port.links.map((link) {
                return link.copyWith(
                  state: LinkState(),
                  id: newIds[link.id],
                  endpoints: (
                    sourceNodeId: newIds[link.endpoints.sourceNodeId]!,
                    sourcePortId: link.endpoints.sourcePortId,
                    targetNodeId: newIds[link.endpoints.targetNodeId]!,
                    targetPortId: link.endpoints.targetPortId,
                  ),
                );
              }).toSet(),
            ),
          );
        }),
      );
    }).toList();

    final linksToRestore = <String, LinkDataModel>{};
    final nodesWithoutLinks = deepCopiedNodes.map((node) {
      for (final port in node.ports.values) {
        for (final link in port.links) {
          linksToRestore[link.id] = link;
        }
      }
      return node.copyWith(
        ports: node.ports.map(
          (id, port) => MapEntry(
            id,
            port.copyWith(links: <LinkDataModel>{}),
          ),
        ),
      );
    }).toList();

    for (final node in nodesWithoutLinks) {
      controller.addNodeFromExisting(node, isHandled: true);
    }
    for (final link in linksToRestore.values) {
      controller.addLinkFromExisting(link, isHandled: true);
    }

    if (extensionData != null && payloadDecoder != null) {
      payloadDecoder!(extensionData, nodesWithoutLinks);
    }

    eventBus.emit(
      PasteSelectionEvent(
        id: const Uuid().v4(),
        position,
        clipboardText,
      ),
    );
  }

  /// Cuts the selected nodes to the clipboard.
  ///
  /// The selected nodes are copied to the clipboard and then removed from the node editor.
  /// The nodes are then removed from the node editor and the selection is cleared.
  Future<String> cutSelection({BuildContext? context}) async {
    final clipboardContent = await copySelection(context: context);
    for (final id in selectedNodeIds.toList()) {
      controller.removeNodeById(id, isHandled: true);
    }
    controller.clearSelection(isHandled: true);

    eventBus.emit(
      CutSelectionEvent(
        id: const Uuid().v4(),
        clipboardContent,
      ),
    );
    return clipboardContent;
  }
}
