#!/bin/zsh

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
source "$repo_root/config/release.env"

expected_feed="https://raw.githubusercontent.com/leeyf2018/Openisland-Reimagine/main/appcast.xml"
expected_releases="https://github.com/leeyf2018/Openisland-Reimagine/releases"

[[ "$REIMAGINE_VERSION" == 1.1.6-reimagine.* ]] || {
    echo "invalid Reimagine version: $REIMAGINE_VERSION" >&2
    exit 1
}
[[ "$REIMAGINE_BUILD_NUMBER" == <-> ]] || {
    echo "build number must be numeric: $REIMAGINE_BUILD_NUMBER" >&2
    exit 1
}
(( REIMAGINE_BUILD_NUMBER > 76 )) || {
    echo "build number must exceed the old upstream maximum (76)" >&2
    exit 1
}
[[ "$REIMAGINE_BUNDLE_ID" == "app.openisland.dev" ]] || {
    echo "bundle identifier drift would break the installed-app migration" >&2
    exit 1
}
[[ "$REIMAGINE_FEED_URL" == "$expected_feed" ]] || {
    echo "unexpected Sparkle feed: $REIMAGINE_FEED_URL" >&2
    exit 1
}
[[ "$REIMAGINE_RELEASES_URL" == "$expected_releases" ]] || {
    echo "unexpected releases URL: $REIMAGINE_RELEASES_URL" >&2
    exit 1
}
[[ "$REIMAGINE_EDDSA_PUBLIC_KEY" == "8E+SpYCjW/jEbNqgo+pGJ3sWYw34cvpSisDovbKwZEU=" ]] || {
    echo "unexpected Reimagine Sparkle public key" >&2
    exit 1
}

effective_files=(
    "$repo_root/scripts/package-app.sh"
    "$repo_root/scripts/launch-dev-app.sh"
    "$repo_root/scripts/update-appcast.sh"
    "$repo_root/Sources/OpenIslandApp/UpdateChecker.swift"
    "$repo_root/appcast.xml"
    "$repo_root/.github/workflows/release.yml"
)

if grep -F "Octane0411/open-vibe-island" "${effective_files[@]}"; then
    echo "upstream release/update URL remains in an effective release surface" >&2
    exit 1
fi

grep -Fq "$expected_feed" "$repo_root/appcast.xml" || {
    echo "appcast self-link is not the Reimagine feed" >&2
    exit 1
}
grep -Fq "$expected_releases" "$repo_root/Sources/OpenIslandApp/UpdateChecker.swift" || {
    echo "UpdateChecker release URL is not Reimagine" >&2
    exit 1
}

echo "release config check passed: $REIMAGINE_VERSION ($REIMAGINE_BUILD_NUMBER)"
