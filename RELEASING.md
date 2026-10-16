# Releasing the workspace

Both packages are currently `1.0.0-dev.1` during the greenfield rewrite. The
implementation is incomplete; this branch has not published either package.

- `packages/sai_nodes_core` is the pure Dart package.
- `packages/sai_nodes` is the Flutter package, depending on the matching core.

For a completed release, publish core first with a `core-vX.Y.Z` tag, then the
Flutter package with `vX.Y.Z` once its dependency is available. Each workflow
verifies the selected package manifest version before publishing. Configure each
package's pub.dev GitHub OIDC publishing policy for its tag pattern. First-time
package registration requires the package owner's normal pub.dev setup.

Before tagging, run the workspace formatting, analysis, both test suites and
`dart tool/verify_core_isolation.dart`. Run publish dry-runs from the selected
package directory; the Flutter package's dry-run requires its core dependency to
be publishable. Add package changelogs and review archives before publication.

The release-assets workflow attaches the workspace source tree to the matching
GitHub Release. No native binaries are distributed by this repository.
