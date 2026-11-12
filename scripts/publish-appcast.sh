#!/bin/zsh
# Called by release.yml after the DMG is available from the public release URL.
set -euo pipefail
cd "${0:A:h:h}"
feed_repo="$PWD/build/feed-repository"
git init "$feed_repo"
git -C "$feed_repo" remote add origin "https://github.com/${GITHUB_REPOSITORY:?}.git"
git -C "$feed_repo" config user.name 'github-actions[bot]'
git -C "$feed_repo" config user.email '41898282+github-actions[bot]@users.noreply.github.com'
git -C "$feed_repo" ls-remote --heads origin refs/heads/updates > "$PWD/build/updates-ref"
if [[ -s "$PWD/build/updates-ref" ]]; then
    git -C "$feed_repo" fetch --depth=1 origin updates
    git -C "$feed_repo" checkout -b updates FETCH_HEAD
    if cmp -s "$feed_repo/appcast.xml" build/updates/appcast.xml; then
        print 'Update feed is already published'
        exit 0
    fi
    python3 scripts/validate-appcast.py --previous "$feed_repo/appcast.xml" "$APP_VERSION"
else
    git -C "$feed_repo" checkout --orphan updates
fi
cp build/updates/appcast.xml "$feed_repo/appcast.xml"
git -C "$feed_repo" add appcast.xml
git -C "$feed_repo" commit -m "Publish Charatify $APP_VERSION update feed"
# A concurrent or manual feed change causes a safe failure; never force-push.
git -C "$feed_repo" push origin HEAD:refs/heads/updates
