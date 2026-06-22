# Releasing Wardlume

Run these **in order, every release.**

## 1. Bump the version
Update `MARKETING_VERSION` (and `CURRENT_PROJECT_VERSION`) in `Wardlume.xcodeproj/project.pbxproj`. The About panel and the Settings sidebar read `CFBundleShortVersionString`.

## 2. Build & package
Build Release, then create both distributables, named `Wardlume-X.Y.Z`:
- **DMG** (unsigned today): stage the `.app` + an `/Applications` symlink, then
  `hdiutil create -volname Wardlume -srcfolder <stage> -ov -format UDZO Wardlume-X.Y.Z.dmg`.
- **PKG**: `productbuild --component <Release>/Wardlume.app /Applications Wardlume-X.Y.Z.pkg`
  (apps installed from a pkg aren't quarantined → no Gatekeeper "damaged" prompt).

> Once enrolled in the Apple Developer Program, use `scripts/notarize.sh X.Y.Z` for a
> Developer-ID-signed + notarized DMG (removes the Gatekeeper warning entirely).
> `*.dmg` / `*.pkg` are gitignored — they're release artifacts, not committed.

## 3. Publish the GitHub release
```sh
gh release create vX.Y.Z Wardlume-X.Y.Z.dmg Wardlume-X.Y.Z.pkg \
  --target main --title "vX.Y.Z — …" --notes-file notes.md
```
Install order in the notes: **Homebrew → .pkg → .dmg**.

## 4. Bump the Homebrew tap cask — EVERY release
In [`arpitagarwal1301/homebrew-tap`](https://github.com/arpitagarwal1301/homebrew-tap), edit
`Casks/wardlume.rb`: update `version` and `sha256` (the sha256 of the **.pkg**), then push. Or:
```sh
brew bump-cask-pr arpitagarwal1301/tap/wardlume --version X.Y.Z
```
The cask points at the `.pkg`, so `brew install --cask wardlume` stays seamless (no "damaged").

## 5. Update docs
README download filename + any version references, and add a `ROADMAP.md` entry.

## Future
Submit the cask to the official `Homebrew/homebrew-cask` once Wardlume clears the notability
bar (~75★ or ~30 forks/watchers) — then users install with no tap. Pairs best with notarization.
