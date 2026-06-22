#!/usr/bin/env bash
#
# check-docs.sh — guard against documentation drift.
#
# Verifies the root markdown docs stay consistent with the app's single
# source of truth (MARKETING_VERSION) and that their internal links and CI
# badges point at things that actually exist. This is the class of mistake
# that lets the README say one version while the release notes / download
# filenames say another.
#
# Run manually:        ./scripts/check-docs.sh
# Runs automatically:  via the pre-push hook (.githooks/pre-push, enable with
#                      `git config core.hooksPath .githooks`) and in CI
#                      (.github/workflows/docs-check.yml).
#
# Exits non-zero if anything is out of sync.
set -uo pipefail

cd "$(git rev-parse --show-toplevel)"

# Root docs we keep in sync. The .cursor/ and .kiro/ markdown are historical
# spec/plan archives and are intentionally excluded.
DOCS=(README.md ROADMAP.md RELEASING.md SAFETY_NOTES.md PRIVACY.md TERMS.md CONTRIBUTING.md)

fail=0
err() { printf '  \033[31m✗\033[0m %s\n' "$1"; fail=1; }
ok()  { printf '  \033[32m✓\033[0m %s\n' "$1"; }

present_docs() {
  local d
  for d in "${DOCS[@]}"; do [ -f "$d" ] && printf '%s\n' "$d"; done
}

# ── 1. Version consistency ────────────────────────────────────────────────
VERSION="$(grep -m1 'MARKETING_VERSION' Wardlume.xcodeproj/project.pbxproj \
  | sed -E 's/.*MARKETING_VERSION = ([0-9.]+);.*/\1/')"

echo "▸ Version (source of truth: MARKETING_VERSION = ${VERSION:-?})"
if [ -z "$VERSION" ]; then
  err "could not read MARKETING_VERSION from Wardlume.xcodeproj/project.pbxproj"
else
  before=$fail
  DOCFILES=()
  while IFS= read -r d; do DOCFILES+=("$d"); done < <(present_docs)

  # Wardlume-X.Y.Z.(pkg|dmg) download filenames must match VERSION.
  # (/dev/null forces grep to always prefix the filename, even for one match.)
  while IFS=: read -r file lineno rest; do
    found="$(grep -oE 'Wardlume-[0-9]+\.[0-9]+\.[0-9]+\.(pkg|dmg)' <<<"$rest" | head -1 \
      | sed -E 's/Wardlume-([0-9]+\.[0-9]+\.[0-9]+)\..*/\1/')"
    [ "$found" = "$VERSION" ] || err "$file:$lineno references Wardlume-$found.* (expected $VERSION)"
  done < <(grep -nE 'Wardlume-[0-9]+\.[0-9]+\.[0-9]+\.(pkg|dmg)' "${DOCFILES[@]}" /dev/null 2>/dev/null)

  # releases/download/vX.Y.Z/ URLs must match VERSION.
  while IFS=: read -r file lineno rest; do
    found="$(grep -oE 'releases/download/v[0-9]+\.[0-9]+\.[0-9]+/' <<<"$rest" | head -1 \
      | sed -E 's#releases/download/v([0-9]+\.[0-9]+\.[0-9]+)/#\1#')"
    [ "$found" = "$VERSION" ] || err "$file:$lineno references releases/download/v$found (expected $VERSION)"
  done < <(grep -nE 'releases/download/v[0-9]+\.[0-9]+\.[0-9]+/' "${DOCFILES[@]}" /dev/null 2>/dev/null)

  [ "$fail" -eq "$before" ] && ok "all download/version references match $VERSION"
fi

# ── 2. Internal links ─────────────────────────────────────────────────────
echo "▸ Internal links (markdown + HTML, local paths only)"
before=$fail
while IFS= read -r file; do
  while IFS= read -r target; do
    case "$target" in
      http://*|https://*|mailto:*|\#*|"") continue ;;
    esac
    path="${target%%#*}"; path="${path%%\?*}"   # strip #anchor and ?query
    [ -z "$path" ] && continue
    [ -e "$path" ] || err "$file: broken link → $target"
  done < <(grep -oE '\]\([^)]+\)|(href|src)="[^"]+"' "$file" \
            | sed -E 's/^\]\(//; s/\)$//; s/^(href|src)="//; s/"$//')
done < <(present_docs)
[ "$fail" -eq "$before" ] && ok "all internal doc links resolve"

# ── 3. CI badge targets ───────────────────────────────────────────────────
echo "▸ CI badges point at existing workflows"
before=$fail
if [ -f README.md ]; then
  while IFS= read -r wf; do
    [ -f ".github/workflows/$wf" ] || \
      err "README badge references workflow '$wf' but .github/workflows/$wf is missing"
  done < <(grep -oE 'actions/workflow/status/[^/]+/[^/]+/[^?"]+\.ya?ml' README.md | sed -E 's#.*/##')
fi
[ "$fail" -eq "$before" ] && ok "all CI badges resolve"

# ── Summary ───────────────────────────────────────────────────────────────
echo
if [ "$fail" -ne 0 ]; then
  echo "✗ Documentation drift detected — fix the above before pushing."
  echo "  (To bypass in an emergency: git push --no-verify)"
  exit 1
fi
echo "✓ Documentation is in sync."
