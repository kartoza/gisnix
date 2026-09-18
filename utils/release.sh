#!/usr/bin/env bash

set -Eeuo pipefail

MAIN_BRANCH="main"

commit=${1:-HEAD}
release_tag=release-$(date "+%Y-%m-%d-%H-%M-%S")

# Check current branch
if [[ "$(git branch --show-current)" != "$MAIN_BRANCH" ]]; then
    echo "Releases can be created only in $MAIN_BRANCH branch ! Exiting ..."
    exit 1
fi

# Verify
echo "Release following commit as a deployment target for production ?"
echo

git show --no-patch "$commit"

echo -e "\nPress [CTRL-C] to abort or [ENTER] to continue."
read -r

# Release
git tag -f -a deploy-prod -m "Current production deployment version"
git tag -a "$release_tag" -m "Released version"

git push -f origin deploy-prod
git push origin "$release_tag"
