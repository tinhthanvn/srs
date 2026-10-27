#!/usr/bin/env bash
# Rebuild cloudcamera-srs:6.0.193-cc1 from the checked-out custom commit.
# Refuses to build unless the checkout is the tested source with the tested patch.
set -euo pipefail

cd "$(dirname "$0")/../.."

CUSTOM_COMMIT=a6565e63c95cb2249f1808182e03f0cde782e77d
BASE_COMMIT=aab043c7dbe038a997e14eb8b4286d089315858e
BASE_DIGEST=sha256:f1067a846d6fd6ee321a407a828ae5ce41713a9acc8e207c053045b775ce73f3
PATCH_SHA=40f531fcfd2c127e32d7da249b988ad12523644da1e820a06bb1d70526258660

test "$(git rev-parse HEAD)" = "$CUSTOM_COMMIT" || {
  echo "FAIL: HEAD is not the tested custom commit ($CUSTOM_COMMIT). Check out tag cc-v6.0.193-cc1." >&2
  exit 1
}
test "$(git rev-parse HEAD^)" = "$BASE_COMMIT" || {
  echo "FAIL: parent commit is not the pinned upstream base." >&2
  exit 1
}
test "$(git diff HEAD^ HEAD | sha256sum | cut -d' ' -f1)" = "$PATCH_SHA" || {
  echo "FAIL: committed patch sha256 does not match." >&2
  exit 1
}

docker buildx build \
  --platform linux/amd64 \
  --label "org.cloudcamera.srs.channel=cc1" \
  --label "org.cloudcamera.srs.patch.sha256=$PATCH_SHA" \
  --label "org.cloudcamera.srs.upstream=ossrs/srs:v6.0-r2" \
  --label "org.cloudcamera.srs.upstream.commit=$BASE_COMMIT" \
  --label "org.cloudcamera.srs.upstream.digest=$BASE_DIGEST" \
  --build-arg SRS_AUTO_PACKAGER=dcis \
  --build-arg CONFARGS='--sanitizer=off --gb28181=on' \
  -t cloudcamera-srs:6.0.193-cc1 .

echo "Built cloudcamera-srs:6.0.193-cc1 from $CUSTOM_COMMIT"
