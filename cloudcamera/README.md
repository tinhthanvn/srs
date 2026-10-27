# Cloud Camera custom SRS (cc1)

This directory contains the Cloud Camera V2 customisation of [SRS](https://github.com/ossrs/srs)
and everything needed to rebuild, verify, deploy and roll back the custom image.

| Item | Value |
| --- | --- |
| Upstream baseline | `ossrs/srs` `v6.0-r2` (SRS `6.0.193`) |
| Upstream commit | `aab043c7dbe038a997e14eb8b4286d089315858e` |
| Upstream image digest | `sha256:f1067a846d6fd6ee321a407a828ae5ce41713a9acc8e207c053045b775ce73f3` |
| Custom branch | `cloudcamera/6.0.193-cc1` |
| Tested source commit | `a6565e63c95cb2249f1808182e03f0cde782e77d` |
| Release tag | `cc-v6.0.193-cc1` |
| Patch | `patches/cloudcamera-srs-6.0.193-cc1.patch` |
| Patch SHA256 | `40f531fcfd2c127e32d7da249b988ad12523644da1e820a06bb1d70526258660` |
| Image | `cloudcamera-srs:6.0.193-cc1` (`linux/amd64`) |

The patch is one commit on top of the untouched upstream base and touches only:

```
trunk/src/app/srs_app_hls.cpp
trunk/src/app/srs_app_hls.hpp
trunk/src/app/srs_app_source.cpp
```

## Layout

```
cloudcamera/
├── BUILD.md                 reproducible build
├── DEPLOYMENT-3-NODES.md    per-node rollout, verification and rollback
├── RELEASE-NOTES.md         release contents and known limits
├── configs/srs.conf.example sanitized node configuration
├── patches/                 the exact patch applied to the custom commit
└── scripts/                 build, verify, install, verify-node, rollback
```

## Licensing and attribution

SRS is MIT licensed (`LICENSE`, Copyright (c) 2013-2025 The SRS Authors). This repository is a
fork; the upstream history, `LICENSE` and attribution are preserved unchanged. The Cloud
Camera changes are limited to the three files listed above.

## Quick start

```bash
git clone https://github.com/tinhthanvn/srs.git
cd srs
git checkout cc-v6.0.193-cc1
bash cloudcamera/scripts/build-image.sh      # linux/amd64 build host
bash cloudcamera/scripts/verify-image.sh
```

Deployment to a streaming node is described in `DEPLOYMENT-3-NODES.md`. The image archive
shipped with a release is preferred over building on the node.
