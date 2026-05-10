#!/usr/bin/env bash

set -e

# Reporting
gpg --version
git --version

if [[ -z $INPUT_GITHUB_TOKEN && $INPUT_PUSH == "true" ]]; then
  echo 'Missing input "github_token: ${{ secrets.GITHUB_TOKEN }}" which is required to push.' >&2
  exit 1
fi

echo "Configuring Git username, email, and pull behavior..."

# Fix #56
git config --global --add safe.directory "*"

git config --local user.name "${INPUT_GIT_NAME}"
git config --local user.email "${INPUT_GIT_EMAIL}"
git config --local pull.rebase true
echo "Git name: $(git config --get user.name)"
echo "Git email: $(git config --get user.email)"

PIP_CMD=('pip' 'install')
if [[ $INPUT_COMMITIZEN_VERSION == 'latest' ]]; then
  PIP_CMD+=('commitizen')
else
  PIP_CMD+=("commitizen==${INPUT_COMMITIZEN_VERSION}")
fi
IFS=" " read -r -a INPUT_EXTRA_REQUIREMENTS <<<"$INPUT_EXTRA_REQUIREMENTS"
PIP_CMD+=("${INPUT_EXTRA_REQUIREMENTS[@]}")
echo "${PIP_CMD[@]}"
"${PIP_CMD[@]}"
echo "Commitizen version: $(cz version)"

if [[ $INPUT_WORKING_DIRECTORY ]]; then
  cd $INPUT_WORKING_DIRECTORY
fi

PREV_REV="$(cz version --project)"
echo "PREVIOUS_REVISION=${PREV_REV}" >>"$GITHUB_ENV"
echo "previous_version=${PREV_REV}" >>"$GITHUB_OUTPUT"

PREV_REV_MAJOR="$(cz version --project --major)"
echo "PREVIOUS_REVISION_MAJOR=${PREV_REV_MAJOR}" >>"$GITHUB_ENV"
echo "previous_version_major=${PREV_REV_MAJOR}" >>"$GITHUB_OUTPUT"
PREV_REV_MINOR="$(cz version --project --minor)"
echo "PREVIOUS_REVISION_MINOR=${PREV_REV_MINOR}" >>"$GITHUB_ENV"
echo "previous_version_minor=${PREV_REV_MINOR}" >>"$GITHUB_OUTPUT"


CZ_CMD=('cz')
if [[ $INPUT_DEBUG == 'true' ]]; then
  CZ_CMD+=('--debug')
fi
if [[ $INPUT_NO_RAISE ]]; then
  CZ_CMD+=('--no-raise' "$INPUT_NO_RAISE")
fi
CZ_CMD+=('bump' '--yes')
if [[ $INPUT_GPG_SIGN == 'true' ]]; then
  CZ_CMD+=('--gpg-sign')
fi
if [[ $INPUT_DRY_RUN == 'true' ]]; then
  CZ_CMD+=('--dry-run')
fi
if [[ $INPUT_CHANGELOG == 'true' ]]; then
  CZ_CMD+=('--changelog')
fi
if [[ $INPUT_PRERELEASE ]]; then
  CZ_CMD+=('--prerelease' "$INPUT_PRERELEASE")
fi
if [[ $INPUT_DEVRELEASE ]]; then
  CZ_CMD+=('--devrelease' "$INPUT_DEVRELEASE")
fi
if [[ $INPUT_LOCAL_VERSION == 'true' ]]; then
  CZ_CMD+=('--local-version')
fi
if [[ $INPUT_COMMIT == 'false' ]]; then
  CZ_CMD+=('--files-only')
fi
if [[ $INPUT_INCREMENT ]]; then
  CZ_CMD+=('--increment' "$INPUT_INCREMENT")
fi
if [[ $INPUT_CHECK_CONSISTENCY == 'true' ]]; then
  CZ_CMD+=('--check-consistency')
fi
if [[ $INPUT_GIT_REDIRECT_STDERR == 'true' ]]; then
  CZ_CMD+=('--git-output-to-stderr')
fi
if [[ $INPUT_BUILD_METADATA ]]; then
  CZ_CMD+=('--build-metadata' "$INPUT_BUILD_METADATA")
fi
if [[ $INPUT_MANUAL_VERSION ]]; then
  CZ_CMD+=("$INPUT_MANUAL_VERSION")
fi

# Capture the would-be next version BEFORE running the actual bump.
# This is used as a fallback for the version output when `cz version --project`
# does not reflect the bump (e.g. version_provider=scm combined with
# commit:false, where neither version files nor git tags are updated).
# Strip `--changelog` and `--changelog-to-stdout` for the `--get-next` call:
# in commitizen < 4.10.1 these flags are incompatible with `--get-next`
# (NotAllowed); in newer versions they emit a no-op warning. Either way
# `--get-next` does not generate a changelog so the flag is unnecessary.
GET_NEXT_CMD=()
for arg in "${CZ_CMD[@]}"; do
  if [[ $arg != '--changelog' && $arg != '--changelog-to-stdout' ]]; then
    GET_NEXT_CMD+=("$arg")
  fi
done
# Failures (no bumpable commits, etc.) are tolerated and produce an empty value.
NEXT_REV_PRE="$("${GET_NEXT_CMD[@]}" --get-next 2>/dev/null || true)"

if [[ $INPUT_CHANGELOG_INCREMENT_FILENAME ]]; then
  CZ_CMD+=('--changelog-to-stdout')
  echo "${CZ_CMD[@]}" ">$INPUT_CHANGELOG_INCREMENT_FILENAME"
  "${CZ_CMD[@]}" >"$INPUT_CHANGELOG_INCREMENT_FILENAME"
else
  echo "${CZ_CMD[@]}"
  "${CZ_CMD[@]}"
fi
if [[ $INPUT_ACTOR ]]; then
  ACTOR=$INPUT_ACTOR
else
  ACTOR=$GITHUB_ACTOR
fi

REV="$(cz version --project)"
NEXT_REV_MAJOR="$(cz version --project --major)"
NEXT_REV_MINOR="$(cz version --project --minor)"

# Fall back to the pre-computed --get-next value when `cz version --project`
# did not reflect the bump. This happens with version_provider=scm and
# commit:false, where the bump does not update any tracked files and no
# tag is created, so the project's reported version remains unchanged.
if [[ $REV == "$PREV_REV" && -n "$NEXT_REV_PRE" && "$NEXT_REV_PRE" != "$PREV_REV" ]]; then
  REV="$NEXT_REV_PRE"
  NEXT_REV_MAJOR="${REV%%.*}"
  NEXT_REV_REST="${REV#*.}"
  NEXT_REV_MINOR="${NEXT_REV_REST%%.*}"
fi

if [[ $REV == "$PREV_REV" ]]; then
  INPUT_PUSH='false'
fi
echo "REVISION=${REV}" >>"$GITHUB_ENV"
echo "version=${REV}" >>"$GITHUB_OUTPUT"
echo "next_version=${REV}" >>"$GITHUB_OUTPUT"

echo "NEXT_REVISION_MAJOR=${NEXT_REV_MAJOR}" >>"$GITHUB_ENV"
echo "next_version_major=${NEXT_REV_MAJOR}" >>"$GITHUB_OUTPUT"
echo "NEXT_REVISION_MINOR=${NEXT_REV_MINOR}" >>"$GITHUB_ENV"
echo "next_version_minor=${NEXT_REV_MINOR}" >>"$GITHUB_OUTPUT"

GITHUB_DOMAIN=${GITHUB_SERVER_URL#*//}
CURRENT_BRANCH="$(git branch --show-current)"
INPUT_BRANCH="${INPUT_BRANCH:-$CURRENT_BRANCH}"
INPUT_REPOSITORY="${INPUT_REPOSITORY:-$GITHUB_REPOSITORY}"

echo "Repository: ${INPUT_REPOSITORY}"
echo "Actor: ${ACTOR}"

if [[ $INPUT_PUSH == 'true' ]]; then
  if [[ $INPUT_MERGE != 'true' && $GITHUB_EVENT_NAME == 'pull_request' ]]; then
    echo "Refusing to push on pull_request event since that would merge the pull request." >&2
    echo "You probably want to run on push to your default branch instead." >&2
  else
    echo "Pushing to branch..."
    REMOTE_REPO="https://${ACTOR}:${INPUT_GITHUB_TOKEN}@${GITHUB_DOMAIN}/${INPUT_REPOSITORY}.git"
    git pull "$REMOTE_REPO" "$INPUT_BRANCH"
    git push "$REMOTE_REPO" "HEAD:${INPUT_BRANCH}" --tags
  fi
else
  echo "Not pushing"
fi
echo "Done."
