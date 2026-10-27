# Release notes — `cc-v6.0.193-cc1`

**Type:** custom SRS maintenance release for Cloud Camera V2
**Status:** tested (isolated smoke) and used for the UAT integration; not yet deployed to the
three remote streaming nodes by this package.

| Item | Value |
| --- | --- |
| Base | `ossrs/srs:v6.0-r2`, SRS `6.0.193` |
| Upstream commit | `aab043c7dbe038a997e14eb8b4286d089315858e` |
| Custom commit | `a6565e63c95cb2249f1808182e03f0cde782e77d` |
| Branch | `cloudcamera/6.0.193-cc1` |
| Tag | `cc-v6.0.193-cc1` |
| Patch SHA256 | `40f531fcfd2c127e32d7da249b988ad12523644da1e820a06bb1d70526258660` |
| Image | `cloudcamera-srs:6.0.193-cc1` |
| Architecture | `linux/amd64` |
| Image ID | `sha256:f4804baf2825f1e4f58d021ab0378a3b8b5728fbe01ce28b31036c7788b739a4` |
| License | MIT (upstream `LICENSE` preserved) |

## Changes

Three files under `trunk/src/app/`:

1. `hls_on_error ignore` now rebuilds the HLS muxer after a packaging error instead of leaving
   HLS disabled until the publisher reconnects.
2. A failed `do_reload()` always clears its reloading guard and retries on a 2 s cadence, so a
   wedge no longer survives a publisher reconnect.
3. A failed `segment_open()` no longer leaves a half-open segment.
4. `flush_video()` reports a missing segment instead of dropping frames silently.

No codec, protocol, DVR, HLS output-format or HTTP-FLV behaviour is changed.

## Verified before release

Isolated two-stream smoke (synthetic H.264 + HEVC, 13/13 PASS):

- HLS playlists present and `MEDIA-SEQUENCE` advancing for both codecs;
- HTTP-FLV `200` with non-zero payload for both codecs;
- DVR segments finalised and `ffprobe` confirms `h264` / `hevc`;
- publisher remains connected while an HLS packaging error is injected, and HLS recovers
  (`hls: self-heal scheduled` → `rebuilt after N failed attempt(s)`);
- two-stream isolation: breaking one stream does not stop the other.

## Known limits

- No multi-hour soak, no disk-full/NFS failure injection, no multi-arch build.
- Self-healing is per-stream inside the SRS process. It does not replace the application-side
  freshness watchdog, and it cannot recover a dead SRS process (Docker restart policy is the
  fallback for that).
- `cgroup`/Docker `HEALTHCHECK` cannot detect a frozen muxer.

## Rollback

Keep `ossrs/srs:v6.0-r2` (`sha256:f1067a846d6fd6ee321a407a828ae5ce41713a9acc8e207c053045b775ce73f3`)
available on every node. Restoring the previous image tag and configuration is sufficient; no
data migration is involved. See `DEPLOYMENT-3-NODES.md` §7.
