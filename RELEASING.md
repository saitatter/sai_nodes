# Releasing SAI Nodes

SAI Nodes is published as a Flutter package on [pub.dev](https://pub.dev/).
There is no platform binary to attach to a release: the package archive contains
the Dart source and the declared grid shader.

## One-time setup

1. Publish the first package version manually with `flutter pub publish`. pub.dev
   requires an interactive login for the first upload.
2. Ensure the account publishing the package is an uploader on pub.dev.
3. Protect release tags so only trusted maintainers can create `vX.Y.Z` tags.

Publishing remains intentionally manual. No pub.dev token or release credential
belongs in GitHub repository secrets.

## Release checklist

1. Update `version` in `pubspec.yaml` using semantic versioning.
2. Add the user-visible changes to the matching heading in `CHANGELOG.md`.
3. Run `dart format --output=none --set-exit-if-changed .`, `flutter analyze`,
   `flutter test`, and `flutter pub publish --dry-run` locally.
4. Merge the version and changelog changes to `main`.
5. Create and push the matching tag:

   ```bash
   git tag vX.Y.Z
   git push origin vX.Y.Z
   ```

6. Publish the package manually from a clean checkout:

   ```bash
   flutter pub publish
   ```

7. Create the GitHub Release manually from the existing `vX.Y.Z` tag and use
   GitHub's generated release notes. There is no binary artifact to attach.

## Assets

The package shader lives at `shaders/grid.frag` and is declared in
`pubspec.yaml`. The repository preview is kept under
`.github/images/node_editor_preview.svg`; replace it with a real capture from an
example application once that application is available. A future `example/`
app should also provide the best source for README screenshots and smoke tests.