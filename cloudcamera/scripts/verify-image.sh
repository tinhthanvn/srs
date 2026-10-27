#!/usr/bin/env bash
# Verify the local custom image without rebuilding or deploying it.
set -u

IMAGE=${IMAGE:-cloudcamera-srs:6.0.193-cc1}
EXPECTED_PATCH=40f531fcfd2c127e32d7da249b988ad12523644da1e820a06bb1d70526258660
EXPECTED_COMMIT=aab043c7dbe038a997e14eb8b4286d089315858e
EXPECTED_FFMPEG=db906a31fe3d835d2fdced0eac9158eda98d1ed760f4d5163c30fb5347f93215

LABELS=$(docker image inspect "$IMAGE" --format '{{json .Config.Labels}}') || exit 1
ARCH=$(docker image inspect "$IMAGE" --format '{{.Architecture}}') || exit 1
echo "labels: $LABELS"
echo "image id: $(docker image inspect "$IMAGE" --format '{{.Id}}')"
echo "arch: $ARCH"

case "$LABELS" in
  *"\"org.cloudcamera.srs.patch.sha256\":\"$EXPECTED_PATCH\""*) ;;
  *) echo "FAIL: patch label mismatch"; exit 1 ;;
esac
case "$LABELS" in
  *"\"org.cloudcamera.srs.upstream.commit\":\"$EXPECTED_COMMIT\""*) ;;
  *) echo "FAIL: upstream commit label mismatch"; exit 1 ;;
esac

VERSION=$(docker run --rm --entrypoint sh "$IMAGE" -c '/usr/local/srs/objs/srs -v' 2>&1 | tail -1)
echo "srs version: $VERSION"
case "$VERSION" in
  *6.0.193*) ;;
  *) echo "FAIL: unexpected SRS version"; exit 1 ;;
esac

FFMPEG=$(docker run --rm --entrypoint sha256sum "$IMAGE" /usr/local/srs/objs/ffmpeg/bin/ffmpeg 2>&1)
echo "ffmpeg: $FFMPEG"
case "$FFMPEG" in
  *"$EXPECTED_FFMPEG"*) ;;
  *) echo "FAIL: bundled ffmpeg checksum differs from the official image"; exit 1 ;;
esac

echo "PASS: image provenance and version verified"
