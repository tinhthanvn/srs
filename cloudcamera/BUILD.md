# Reproducible build — Cloud Camera SRS cc1

The shipped image `cloudcamera-srs:6.0.193-cc1` was built from tag `cc-v6.0.193-cc1`
(commit `a6565e63c95cb2249f1808182e03f0cde782e77d`), which is one commit on top of the
untouched upstream `v6.0-r2` (`aab043c7dbe038a997e14eb8b4286d089315858e`).

## Requirements

- Linux host, `linux/amd64` (or Docker Desktop with buildx on Windows/macOS)
- Docker 24+ with BuildKit/buildx
- ~10 GB free disk for the builder and runtime layers
- Network access to pull `ossrs/srs:ubuntu20` and `ubuntu:focal`

## Verify the checkout

```bash
git clone https://github.com/tinhthanvn/srs.git
cd srs
git checkout cc-v6.0.193-cc1

# Must print a6565e63c95cb2249f1808182e03f0cde782e77d
git rev-parse HEAD

# Must print 40f531fcfd2c127e32d7da249b988ad12523644da1e820a06bb1d70526258660
git diff HEAD^ HEAD | sha256sum | cut -d' ' -f1

# Optional: the patch file in the repository must match the commit
sha256sum cloudcamera/patches/cloudcamera-srs-6.0.193-cc1.patch
```

If any value differs, stop — the source is not the tested source.

## Build

```bash
docker buildx build \
  --platform linux/amd64 \
  --label org.cloudcamera.srs.channel=cc1 \
  --label org.cloudcamera.srs.patch.sha256=40f531fcfd2c127e32d7da249b988ad12523644da1e820a06bb1d70526258660 \
  --label org.cloudcamera.srs.upstream=ossrs/srs:v6.0-r2 \
  --label org.cloudcamera.srs.upstream.commit=aab043c7dbe038a997e14eb8b4286d089315858e \
  --label org.cloudcamera.srs.upstream.digest=sha256:f1067a846d6fd6ee321a407a828ae5ce41713a9acc8e207c053045b775ce73f3 \
  --build-arg SRS_AUTO_PACKAGER=dcis \
  --build-arg CONFARGS='--sanitizer=off --gb28181=on' \
  -t cloudcamera-srs:6.0.193-cc1 .
```

`cloudcamera/scripts/build-image.sh` performs the same command after asserting the checkout,
the base commit and the patch SHA256.

## Verify the image

```bash
bash cloudcamera/scripts/verify-image.sh
```

It checks the labels (channel, patch, upstream commit/digest), the in-container
`objs/srs -v` version (`6.0.193`) and the bundled ffmpeg checksum
(`db906a31fe3d835d2fdced0eac9158eda98d1ed760f4d5163c30fb5347f93215`, identical to the
official image).

A rebuild is not bit-for-bit reproducible (timestamps and layer IDs differ). Treat the
labels, version and patch identity as the provenance contract; the released archive
checksum is the artifact contract.

## What the patch changes

See `patches/cloudcamera-srs-6.0.193-cc1.patch` and the release notes. In short:

1. `hls_on_error ignore` rebuilds the HLS muxer after a packaging error instead of leaving
   HLS disabled until the publisher reconnects.
2. A failed `do_reload()` clears its guard and retries on a 2 s cadence.
3. A failed `segment_open()` no longer leaves a half-open segment.
4. `flush_video()` reports a missing segment instead of dropping frames silently.

No codec, protocol, DVR or HTTP-FLV behaviour is altered.
