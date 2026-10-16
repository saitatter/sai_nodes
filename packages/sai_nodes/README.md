# sai_nodes

Flutter graph editor package in the Sai Nodes workspace. Its pure Dart document
foundation is the sibling `sai_nodes_core` package.

The 1.0 rewrite is in progress on `rewrite/graph-1.0`. Phase A relocates the
existing canvas unchanged in behavior and introduces the new core. The canvas
still uses its existing internal models until the scene/controller cutover;
it is not yet a renderer for the new `GraphDocument`.

The final API will replace the 0.x editor API without compatibility adapters.
See `docs/greenfield-plan.md` and `docs/greenfield-progress.md` in the repository.
