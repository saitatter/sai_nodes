# Releasing the workspace

The first stable immutable graph release is `1.0.0` for both packages. This is a
breaking replacement of the 0.x API and saved formats; no compatibility decoder
or automatic migration is provided.

- `packages/sai_nodes_core` is the pure Dart package.
- `packages/sai_nodes` is the Flutter package, depending on the matching core.

For a completed release, publish core first with a `core-vX.Y.Z` tag, then the
Flutter package with `vX.Y.Z` once its dependency is available. Each workflow
verifies the selected package manifest version before publishing. Configure each
package's pub.dev GitHub OIDC publishing policy for its tag pattern. For the first
core release, publish from packages/sai_nodes_core with `dart pub publish` using
the owner's local pub.dev authentication. New packages cannot use OIDC for their
initial registration. Then publish the Flutter package through its `v1.0.0` tag;
that GitHub Release describes both workspace packages. Configure the new core
package's automation policy before using `core-vX.Y.Z` tags for later releases.

Before tagging, run the workspace formatting, analysis, both test suites and
`dart tool/verify_core_isolation.dart`. Run publish dry-runs from the selected
package directory; the Flutter package's dry-run requires its core dependency to
be publishable. Add package changelogs and review archives before publication.

The release-assets workflow attaches the workspace source tree to the matching
GitHub Release. No native binaries are distributed by this repository.

Release notes must mention the Dart SDK minimum (currently 3.12), the new core
dependency and the incompatible API/format change. Performance measurements in
docs/performance.md describe local wall-clock costs, not frame-rate guarantees.
