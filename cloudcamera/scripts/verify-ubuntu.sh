#!/usr/bin/env bash
# Verify a node running cloudcamera-srs:6.0.193-cc1. Read-only: it starts
# nothing and changes nothing. Checks that are not configured are reported SKIP,
# never PASS.
#
#   ./verify-ubuntu.sh
#   SRS_CONTAINER=cloudcamera-v2-srs HLS_URL=http://127.0.0.1:8080/hls/cam1.m3u8 \
#     FLV_URL=http://127.0.0.1:8080/live/cam1.flv DVR_DIR=/srv/srs/media/dvr \
#     EXPECTED_STREAMS=5 ./verify-ubuntu.sh
#
# Exit codes: 0 no failures, 1 at least one FAIL.

set -uo pipefail

IMAGE_TAG="${CC_SRS_IMAGE:-cloudcamera-srs:6.0.193-cc1}"
EXPECTED_IMAGE_ID="sha256:f4804baf2825f1e4f58d021ab0378a3b8b5728fbe01ce28b31036c7788b739a4"
EXPECTED_PATCH_SHA="40f531fcfd2c127e32d7da249b988ad12523644da1e820a06bb1d70526258660"
EXPECTED_VERSION="6.0.193"

CONTAINER="${SRS_CONTAINER:-cloudcamera-srs}"
API_PORT="${CC_API_PORT:-1985}"
HTTP_PORT="${CC_HTTP_PORT:-8080}"
SRS_CONF="${CC_SRS_CONF:-}"
EXPECTED_STREAMS="${EXPECTED_STREAMS:-}"
DVR_DIR="${DVR_DIR:-}"

fails=0
pass() { printf 'PASS  %s\n' "$*"; }
warn() { printf 'WARN  %s\n' "$*"; }
skip() { printf 'SKIP  %s\n' "$*"; }
fail() { printf 'FAIL  %s\n' "$*"; fails=$((fails + 1)); }

printf '== image provenance ==\n'
if ! docker image inspect "$IMAGE_TAG" >/dev/null 2>&1; then
  fail "image $IMAGE_TAG is not loaded"
else
  id="$(docker image inspect "$IMAGE_TAG" --format '{{.Id}}')"
  [ "$id" = "$EXPECTED_IMAGE_ID" ] && pass "image id $id" || fail "image id $id != $EXPECTED_IMAGE_ID"

  labels="$(docker image inspect "$IMAGE_TAG" --format '{{json .Config.Labels}}')"
  printf '%s' "$labels" | grep -q "$EXPECTED_PATCH_SHA" \
    && pass "patch label $EXPECTED_PATCH_SHA" || fail "patch label missing or different"

  version="$(docker run --rm --entrypoint ./objs/srs "$IMAGE_TAG" -v 2>&1 | tail -n1)"
  case "$version" in
    *"$EXPECTED_VERSION"*) pass "srs -v $version" ;;
    *) fail "unexpected srs version: $version" ;;
  esac
fi

printf '\n== configuration test ==\n'
if [ -n "$SRS_CONF" ] && [ -f "$SRS_CONF" ]; then
  if out="$(docker run --rm -v "$SRS_CONF:/usr/local/srs/conf/srs.conf:ro" "$IMAGE_TAG" \
              ./objs/srs -t -c conf/srs.conf 2>&1)"; then
    pass "srs -t accepted $SRS_CONF"
  else
    fail "srs -t rejected $SRS_CONF"
    printf '%s\n' "$out" | tail -n 20
  fi
else
  skip "set CC_SRS_CONF to test a config file"
fi

printf '\n== container ==\n'
state="$(docker inspect "$CONTAINER" --format '{{.State.Status}}' 2>/dev/null || true)"
if [ -z "$state" ]; then
  fail "container $CONTAINER not found"
else
  [ "$state" = "running" ] && pass "container $CONTAINER running" || fail "container $CONTAINER is $state"
  running_image="$(docker inspect "$CONTAINER" --format '{{.Config.Image}}')"
  [ "$running_image" = "$IMAGE_TAG" ] && pass "container image $running_image" \
    || fail "container runs $running_image, expected $IMAGE_TAG"
fi

printf '\n== api and publishers ==\n'
if versions="$(curl -fsS -m 5 "http://127.0.0.1:$API_PORT/api/v1/versions" 2>/dev/null)"; then
  pass "api http://127.0.0.1:$API_PORT/api/v1/versions"
else
  fail "api not answering on 127.0.0.1:$API_PORT"
  versions=""
fi

streams_json="$(curl -fsS -m 5 "http://127.0.0.1:$API_PORT/api/v1/streams/?count=200" 2>/dev/null || true)"
if [ -n "$streams_json" ]; then
  names="$(printf '%s' "$streams_json" | grep -o '"name":"[^"]*"' | cut -d'"' -f4 | sort -u)"
  count="$(printf '%s' "$names" | grep -c . || true)"
  printf '      streams: %s\n' "$(printf '%s' "$names" | paste -sd, - 2>/dev/null || true)"
  if [ -n "$EXPECTED_STREAMS" ]; then
    [ "$count" -ge "$EXPECTED_STREAMS" ] && pass "$count publishers (expected >= $EXPECTED_STREAMS)" \
      || fail "$count publishers, expected >= $EXPECTED_STREAMS"
  else
    [ "$count" -gt 0 ] && pass "$count publishers" || warn "0 publishers (fine on an idle node)"
  fi
else
  fail "publisher inventory unavailable"
fi

printf '\n== hls ==\n'
if [ -n "${HLS_URL:-}" ]; then
  seq1="$(curl -fsS -m 5 "$HLS_URL" 2>/dev/null | grep -m1 '^#EXT-X-MEDIA-SEQUENCE:' | tr -dc '0-9' || true)"
  sleep 4
  seq2="$(curl -fsS -m 5 "$HLS_URL" 2>/dev/null | grep -m1 '^#EXT-X-MEDIA-SEQUENCE:' | tr -dc '0-9' || true)"
  if [ -z "$seq1" ] || [ -z "$seq2" ]; then
    fail "playlist unreadable at $HLS_URL"
  elif [ "$seq2" -gt "$seq1" ]; then
    pass "media sequence $seq1 -> $seq2"
  else
    fail "media sequence frozen at $seq1"
  fi
else
  skip "set HLS_URL to check playlist freshness"
fi

printf '\n== http-flv origin ==\n'
if [ -n "${FLV_URL:-}" ]; then
  read -r code ctype < <(curl -m 3 -s -o /dev/null -w '%{http_code} %{content_type}' "$FLV_URL" 2>/dev/null || echo "000 -")
  [ "$code" = "200" ] && pass "flv 200 ($ctype)" || fail "flv returned $code"
  printf '      raw origin must NOT be reachable from the internet — verify firewall/SG\n'
else
  skip "set FLV_URL to check the origin stream"
fi

printf '\n== dvr ==\n'
if [ -n "$DVR_DIR" ] && [ -d "$DVR_DIR" ]; then
  newest="$(find "$DVR_DIR" -type f -name '*.mp4' -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -n1 | cut -d' ' -f2-)"
  if [ -n "$newest" ]; then
    age_min=$(( ( $(date +%s) - $(stat -c %Y "$newest") ) / 60 ))
    [ "$age_min" -le 15 ] && pass "newest segment ${age_min}m old: $newest" \
      || fail "newest segment ${age_min}m old (recording may be stalled): $newest"
  else
    warn "no .mp4 under $DVR_DIR"
  fi
else
  skip "set DVR_DIR to check recent segments"
fi

printf '\n== self-heal history (informational) ==\n'
if [ -n "$state" ]; then
  heal="$(docker logs "$CONTAINER" 2>&1 | grep -c 'hls: self-heal scheduled' || true)"
  printf 'INFO  %s self-heal event(s) in the current container log\n' "$heal"
fi

printf '\n== result ==\n'
if [ "$fails" -eq 0 ]; then
  printf 'VERIFY: PASS\n'
  exit 0
fi
printf 'VERIFY: FAIL (%s failed check(s))\n' "$fails"
exit 1
