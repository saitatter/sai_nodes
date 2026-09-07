# Releasing SAI Nodes

SAI Nodes is published as a Flutter package on [pub.dev](https://pub.dev/).
There is no platform binary to attach to a release. GitHub Actions publishes the
package to pub.dev and attaches source archives containing the Dart source and
the declared grid shader.

## One-time setup

1. Publish the first package version manually with `flutter pub publish`. pub.dev
   requires an interactive login for the first upload.
2. Ensure the account publishing the package is an uploader on pub.dev.
3. In the pub.dev package admin page, enable GitHub Actions automated publishing
   for `saitatter/sai_nodes` with the tag pattern `v{{version}}`.
4. Protect release tags so only trusted maintainers can create `vX.Y.Z` tags.

Publishing uses a short-lived GitHub OIDC token. No pub.dev token or release
credential belongs in GitHub repository secrets.

## Release checklist

1. Update `version` in `pubspec.yaml` using semantic versioning.
2. Add the user-visible changes to the matching heading in `CHANGELOG.md`.
3. Run `dart format --output=none --set-exit-if-changed .`, `flutter analyze`,
   `flutter test`, and `flutter pub publish --dry-run` locally.
4. Merge the version and changelog changes to `main`.
5. Create a GitHub Release from `main`, using a new tag that matches the package
   version, for example `v0.2.1`.

   Creating the tag starts the pub.dev publishing workflow. Publishing and
   archive upload are complete only after both GitHub Actions workflows pass.

   If you prefer the command line, create and push the matching tag first:

   ```bash
   git tag vX.Y.Z
   git push origin vX.Y.Z
   ```

6. Create the GitHub Release from the existing `vX.Y.Z` tag and use GitHub's
   generated release notes. The workflow attaches `.zip` and `.tar.gz` source
   archives automatically.

## Assets

The package shader lives at `shaders/grid.frag` and is declared in
`pubspec.yaml`. The repository preview is kept under
`.github/images/node_editor_preview.svg`; replace it with a real capture from an
example application once that application is available. A future `example/`
app should also provide the best source for README screenshots and smoke tests.
