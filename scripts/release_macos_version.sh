#!/usr/bin/env bash
# Bump pubspec version, build the macOS release app, commit, tag, and push.
#
# Examples:
#   bash scripts/release_macos_version.sh
#   bash scripts/release_macos_version.sh --version 1.0.8 --build-number 9
#   bash scripts/release_macos_version.sh --yes --remote github

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PUBSPEC_PATH="$ROOT_DIR/pubspec.yaml"
PACKAGE_SCRIPT="$ROOT_DIR/scripts/package_macos_release_app.sh"
TAG_PREFIX="v"
VERSION=""
BUILD_NUMBER=""
REMOTE=""
YES=0

usage() {
  cat <<'EOF'
Usage: bash scripts/release_macos_version.sh [options]

Options:
  --version X.Y.Z       Override the default version read from latest tag + 1.
  --build-number N      Override the default pubspec build number + 1.
  --remote NAME         Push to this git remote. Defaults to upstream remote.
  --yes                 Skip interactive confirmation and use resolved values.
  -h, --help            Show this help.
EOF
}

fail() {
  echo "error: $*" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      VERSION="${2:-}"
      shift 2
      ;;
    --build-number)
      BUILD_NUMBER="${2:-}"
      shift 2
      ;;
    --remote)
      REMOTE="${2:-}"
      shift 2
      ;;
    --yes)
      YES=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "unknown option: $1"
      ;;
  esac
done

cd "$ROOT_DIR"

command -v git >/dev/null 2>&1 || fail "git is required."
[[ -f "$PUBSPEC_PATH" ]] || fail "pubspec.yaml not found."
[[ -f "$PACKAGE_SCRIPT" ]] || fail "package script not found: $PACKAGE_SCRIPT"

if [[ -n "$(git status --porcelain)" ]]; then
  fail "working tree is not clean. Commit or stash existing changes before releasing."
fi

current_branch="$(git branch --show-current)"
[[ -n "$current_branch" ]] || fail "not on a named git branch."

latest_tag="$(
  git tag --list "${TAG_PREFIX}[0-9]*" --sort=-v:refname \
    | grep -E "^${TAG_PREFIX}[0-9]+\.[0-9]+\.[0-9]+$" \
    | head -n 1 || true
)"
[[ -n "$latest_tag" ]] || fail "no release tag found, expected tags like ${TAG_PREFIX}1.0.7."

tag_version="${latest_tag#"$TAG_PREFIX"}"
IFS='.' read -r major minor patch <<<"$tag_version"
[[ "$major" =~ ^[0-9]+$ && "$minor" =~ ^[0-9]+$ && "$patch" =~ ^[0-9]+$ ]] \
  || fail "latest tag is not a semantic version: $latest_tag"

default_version="$major.$minor.$((patch + 1))"
pubspec_version_line="$(grep -E '^version:[[:space:]]*[^[:space:]#]+' "$PUBSPEC_PATH" | head -n 1 || true)"
[[ -n "$pubspec_version_line" ]] || fail "pubspec.yaml does not contain a version line."

current_pubspec_version="$(
  sed -E 's/^version:[[:space:]]*([^[:space:]#]+).*/\1/' <<<"$pubspec_version_line"
)"
current_build_number=""
if [[ "$current_pubspec_version" == *+* ]]; then
  current_build_number="${current_pubspec_version##*+}"
fi
if [[ "$current_build_number" =~ ^[0-9]+$ ]]; then
  default_build_number="$((current_build_number + 1))"
else
  default_build_number=1
fi

if [[ -z "$VERSION" ]]; then
  VERSION="$default_version"
fi
if [[ -z "$BUILD_NUMBER" ]]; then
  BUILD_NUMBER="$default_build_number"
fi

if [[ -z "$REMOTE" ]]; then
  upstream="$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"
  if [[ "$upstream" == */* ]]; then
    REMOTE="${upstream%%/*}"
  else
    REMOTE="$(git remote | head -n 1 || true)"
  fi
fi
[[ -n "$REMOTE" ]] || fail "no git remote found. Pass --remote NAME."

if [[ "$YES" != "1" ]]; then
  echo "Latest tag:       $latest_tag"
  echo "Current pubspec:  $current_pubspec_version"
  echo "Default release:  ${VERSION}+${BUILD_NUMBER}"
  echo "Target remote:    $REMOTE"
  echo

  read -r -p "Version [$VERSION]: " input_version
  if [[ -n "$input_version" ]]; then
    VERSION="$input_version"
  fi

  read -r -p "Build number [$BUILD_NUMBER]: " input_build_number
  if [[ -n "$input_build_number" ]]; then
    BUILD_NUMBER="$input_build_number"
  fi

  read -r -p "Remote [$REMOTE]: " input_remote
  if [[ -n "$input_remote" ]]; then
    REMOTE="$input_remote"
  fi

  echo
  read -r -p "Release ${VERSION}+${BUILD_NUMBER}, tag ${TAG_PREFIX}${VERSION}, push to ${REMOTE}/${current_branch}? [y/N] " confirm
  [[ "$confirm" == "y" || "$confirm" == "Y" ]] || fail "release cancelled."
fi

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "version must look like X.Y.Z: $VERSION"
[[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]] || fail "build number must be a positive integer: $BUILD_NUMBER"
git remote get-url "$REMOTE" >/dev/null 2>&1 || fail "git remote does not exist: $REMOTE"

release_tag="${TAG_PREFIX}${VERSION}"
if git rev-parse -q --verify "refs/tags/$release_tag" >/dev/null; then
  fail "tag already exists: $release_tag"
fi

next_pubspec_version="${VERSION}+${BUILD_NUMBER}"
tmp_pubspec="$(mktemp "${TMPDIR:-/tmp}/mise-gui-pubspec.XXXXXX")"
awk -v version="$next_pubspec_version" '
  BEGIN { updated = 0 }
  /^version:[[:space:]]*/ && updated == 0 {
    sub(/^version:[[:space:]]*[^[:space:]#]+/, "version: " version)
    updated = 1
  }
  { print }
  END {
    if (updated == 0) {
      exit 42
    }
  }
' "$PUBSPEC_PATH" > "$tmp_pubspec" || {
  rm -f "$tmp_pubspec"
  fail "failed to update pubspec version."
}
mv "$tmp_pubspec" "$PUBSPEC_PATH"

echo "Updated pubspec.yaml to version: $next_pubspec_version"
echo "Running macOS release package script..."
bash "$PACKAGE_SCRIPT"

git add -u
if git diff --cached --quiet; then
  fail "nothing was staged for commit after release build."
fi

commit_message="build: 构建${VERSION}版本软件"
git commit -m "$commit_message"
git tag -a "$release_tag" -m "$commit_message"
git push "$REMOTE" "$current_branch"
git push "$REMOTE" "$release_tag"

echo "Released $release_tag and pushed to $REMOTE."
