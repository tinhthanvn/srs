#!/usr/bin/env bash
# Roll one node back to the image and srs.conf recorded by install-ubuntu.sh.
# Destructive by design, so it prints the plan and refuses to act without
# --confirm. Backups are never deleted.
#
#   ./rollback-ubuntu.sh --backup /root/srs-rollback-20261027-101500 \
#                        --compose /opt/cloudcamera-srs/6.0.193-cc1/docker-compose.yml --confirm
#
#   --project NAME   compose project name (default: CC_PROJECT or cloudcamera-srs)
#
# Exit codes: 0 rolled back, 2 confirmation missing, 1 rollback failed.

set -uo pipefail

BACKUP_DIR=""
COMPOSE_FILE=""
PROJECT="${CC_PROJECT:-cloudcamera-srs}"
CONFIRMED=0

usage() {
  sed -n '2,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit 2
}

while [ $# -gt 0 ]; do
  case "$1" in
    --backup)  BACKUP_DIR="${2:-}"; shift 2 ;;
    --compose) COMPOSE_FILE="${2:-}"; shift 2 ;;
    --project) PROJECT="${2:-}"; shift 2 ;;
    --confirm) CONFIRMED=1; shift ;;
    -h|--help) usage ;;
    *) printf 'unknown argument: %s\n' "$1" >&2; usage ;;
  esac
done

fail() { printf 'FAIL  %s\n' "$*" >&2; exit 1; }
say()  { printf '%s\n' "$*"; }

[ -n "$BACKUP_DIR" ] || fail "--backup is required"
[ -d "$BACKUP_DIR" ] || fail "backup directory $BACKUP_DIR does not exist"
[ -f "$BACKUP_DIR/backup-meta.env" ] || fail "$BACKUP_DIR/backup-meta.env missing"
[ -f "$COMPOSE_FILE" ] || fail "--compose must point at the compose file used for the rollout"

# shellcheck disable=SC1091
. "$BACKUP_DIR/backup-meta.env"

[ -n "${PREV_IMAGE:-}" ] || fail "no previous image recorded in $BACKUP_DIR/backup-meta.env"
docker image inspect "$PREV_IMAGE" >/dev/null 2>&1 \
  || fail "previous image $PREV_IMAGE is not present on this node (load the rollback tar first)"

if docker compose version >/dev/null 2>&1; then
  DOCKER_COMPOSE=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
  DOCKER_COMPOSE=(docker-compose)
else
  fail "neither 'docker compose' nor 'docker-compose' is available"
fi

say "== rollback plan =="
say "  project        : $PROJECT"
say "  compose file   : $COMPOSE_FILE"
say "  current image  : ${NEW_IMAGE:-unknown} (${NEW_IMAGE_ID:-unknown})"
say "  previous image : $PREV_IMAGE"
say "  container name : ${PREV_CONTAINER:-<compose default>}"
say "  config restore : ${PREV_CONF_SOURCE:-<none>} <- $BACKUP_DIR/srs.conf.previous"
say "  backup kept at : $BACKUP_DIR"
say ""
say "This stops the node's SRS container and restarts it on the previous image."
say "Every publisher on the node reconnects."

if [ "$CONFIRMED" -ne 1 ]; then
  say ""
  say "DRY RUN — nothing changed. Re-run with --confirm to execute."
  exit 2
fi

set -e

if [ -n "${PREV_CONF_SOURCE:-}" ] && [ -f "$BACKUP_DIR/srs.conf.previous" ]; then
  if [ -f "$PREV_CONF_SOURCE" ]; then
    cp "$PREV_CONF_SOURCE" "$BACKUP_DIR/srs.conf.failed-$(date +%Y%m%d-%H%M%S)"
  fi
  cp "$BACKUP_DIR/srs.conf.previous" "$PREV_CONF_SOURCE"
  say "PASS  restored $PREV_CONF_SOURCE"
else
  say "WARN  no config backup to restore; the node keeps its current srs.conf"
fi

say ""
say "== stopping ${PROJECT} =="
"${DOCKER_COMPOSE[@]}" -p "$PROJECT" -f "$COMPOSE_FILE" down

say ""
say "== starting previous image =="
CC_SRS_IMAGE="$PREV_IMAGE" \
CC_SRS_CONTAINER="${PREV_CONTAINER:-cloudcamera-srs}" \
  "${DOCKER_COMPOSE[@]}" -p "$PROJECT" -f "$COMPOSE_FILE" up -d

say ""
say "PASS  rollback started. Verify before closing the incident:"
say "  docker ps --filter name=${PREV_CONTAINER:-cloudcamera-srs}"
say "  curl -s http://127.0.0.1:\${CC_API_PORT:-1985}/api/v1/streams/?count=200"
say "  curl -s http://127.0.0.1:\${CC_HTTP_PORT:-8080}/<app>/<stream>/<stream>.m3u8 | head"
say "  check a new DVR segment appears, and that every expected camera republished"
