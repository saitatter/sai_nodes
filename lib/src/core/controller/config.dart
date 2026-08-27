/// A class that defines the behavior of a node editor.
///
/// This class is responsible for handling the interactions and
/// behaviors associated with a node editor, such as node selection,
/// movement, and other editor-specific functionalities.
class NodeEditorConfig {
  final bool enableZoom;
  final double zoomSensitivity;
  final double minZoom;
  final double maxZoom;
  final bool enablePan;
  final double panSensitivity;
  final double maxPanX;
  final double maxPanY;
  final bool enableKineticScrolling;
  final bool enableAutoScrolling;
  final bool enableAreaSelection;
  final bool enableSnapToGrid;
  final double snapToGridSize;

  /// Minimum fixed node width in logical editor units.
  final double minNodeWidth;

  /// Minimum fixed node height in logical editor units.
  final double minNodeHeight;

  /// Maximum fixed node width in logical editor units.
  final double maxNodeWidth;

  /// Maximum fixed node height in logical editor units.
  final double maxNodeHeight;

  /// Distance from a link path at which pointer interaction is accepted.
  final double linkHitTestTolerance;

  /// Distance from a port at which pointer interaction is accepted.
  final double portHitTestTolerance;

  /// Whether default nodes expose a resize handle.
  final bool enableNodeResize;
  final bool enableAutoPlacement;
  final bool autoSave;
  final bool autoBuildGraph;
  final bool autoRunGraph;
  final Duration autoSaveInterval;
  final Duration manualSaveDebounce;
  final Duration autoBuildGraphDelay;
  final Duration autoRunGraphDelay;

  const NodeEditorConfig({
    this.enableZoom = true,
    this.zoomSensitivity = 0.1,
    this.minZoom = 0.1,
    this.maxZoom = 10.0,
    this.enablePan = true,
    this.panSensitivity = 1.0,
    this.maxPanX = 100000.0,
    this.maxPanY = 100000.0,
    this.enableKineticScrolling = true,
    this.enableAutoScrolling = true,
    this.enableAreaSelection = true,
    this.enableSnapToGrid = true,
    this.snapToGridSize = 64.0,
    this.minNodeWidth = 80.0,
    this.minNodeHeight = 48.0,
    this.maxNodeWidth = 1600.0,
    this.maxNodeHeight = 1200.0,
    this.linkHitTestTolerance = 4.0,
    this.portHitTestTolerance = 4.0,
    this.enableNodeResize = false,
    this.enableAutoPlacement = false,
    this.autoSave = false,
    this.autoBuildGraph = true,
    this.autoRunGraph = true,
    this.autoSaveInterval = const Duration(seconds: 30),
    this.manualSaveDebounce = const Duration(seconds: 2),
    this.autoBuildGraphDelay = const Duration(seconds: 5),
    this.autoRunGraphDelay = const Duration(seconds: 5),
  })  : assert(minNodeWidth > 0 && minNodeWidth < double.infinity),
        assert(minNodeHeight > 0 && minNodeHeight < double.infinity),
        assert(maxNodeWidth >= minNodeWidth && maxNodeWidth < double.infinity),
        assert(
          maxNodeHeight >= minNodeHeight && maxNodeHeight < double.infinity,
        ),
        assert(
          linkHitTestTolerance >= 0 && linkHitTestTolerance < double.infinity,
        ),
        assert(
          portHitTestTolerance >= 0 && portHitTestTolerance < double.infinity,
        );

  NodeEditorConfig copyWith({
    bool? enableZoom,
    double? zoomSensitivity,
    double? minZoom,
    double? maxZoom,
    bool? enablePan,
    double? panSensitivity,
    double? maxPanX,
    double? maxPanY,
    bool? enableKineticScrolling,
    bool? enableAutoScrolling,
    bool? enableAreaSelection,
    bool? enableSnapToGrid,
    double? snapToGridSize,
    double? minNodeWidth,
    double? minNodeHeight,
    double? maxNodeWidth,
    double? maxNodeHeight,
    double? linkHitTestTolerance,
    double? portHitTestTolerance,
    bool? enableNodeResize,
    bool? enableAutoPlacement,
    bool? autoSave,
    bool? autoBuildGraph,
    bool? autoRunGraph,
    Duration? autoSaveInterval,
    Duration? manualSaveDebounce,
    Duration? autoBuildGraphDelay,
    Duration? autoRunGraphDelay,
  }) {
    return NodeEditorConfig(
      enableZoom: enableZoom ?? this.enableZoom,
      zoomSensitivity: zoomSensitivity ?? this.zoomSensitivity,
      minZoom: minZoom ?? this.minZoom,
      maxZoom: maxZoom ?? this.maxZoom,
      enablePan: enablePan ?? this.enablePan,
      panSensitivity: panSensitivity ?? this.panSensitivity,
      maxPanX: maxPanX ?? this.maxPanX,
      maxPanY: maxPanY ?? this.maxPanY,
      enableKineticScrolling:
          enableKineticScrolling ?? this.enableKineticScrolling,
      enableAutoScrolling: enableAutoScrolling ?? this.enableAutoScrolling,
      enableAreaSelection: enableAreaSelection ?? this.enableAreaSelection,
      enableSnapToGrid: enableSnapToGrid ?? this.enableSnapToGrid,
      snapToGridSize: snapToGridSize ?? this.snapToGridSize,
      minNodeWidth: minNodeWidth ?? this.minNodeWidth,
      minNodeHeight: minNodeHeight ?? this.minNodeHeight,
      maxNodeWidth: maxNodeWidth ?? this.maxNodeWidth,
      maxNodeHeight: maxNodeHeight ?? this.maxNodeHeight,
      linkHitTestTolerance: linkHitTestTolerance ?? this.linkHitTestTolerance,
      portHitTestTolerance: portHitTestTolerance ?? this.portHitTestTolerance,
      enableNodeResize: enableNodeResize ?? this.enableNodeResize,
      enableAutoPlacement: enableAutoPlacement ?? this.enableAutoPlacement,
      autoSave: autoSave ?? this.autoSave,
      autoBuildGraph: autoBuildGraph ?? this.autoBuildGraph,
      autoRunGraph: autoRunGraph ?? this.autoRunGraph,
      autoSaveInterval: autoSaveInterval ?? this.autoSaveInterval,
      manualSaveDebounce: manualSaveDebounce ?? this.manualSaveDebounce,
      autoBuildGraphDelay: autoBuildGraphDelay ?? this.autoBuildGraphDelay,
      autoRunGraphDelay: autoRunGraphDelay ?? this.autoRunGraphDelay,
    );
  }
}
