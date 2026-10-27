#!/usr/bin/env bash
# Load and verify cloudcamera-srs:6.0.193-cc1 on ONE Ubuntu SRS node and back up
# the current SRS state. It never stops, restarts or removes a running container.
#
#   sudo ./install-ubuntu.sh
#   sudo SRS_CONTAINER=cloudcamera-v2-srs CC_SRS_CONF=/srv/srs/srs.conf \
#        CC_MEDIA_DIR=/srv/srs/media ./install-ubuntu.sh
#
# Exit codes: 0 ready for manual deployment, 1 preflight/verification failed.

set -euo pipefail

IMAGE_TAG="cloudcamera-srs:6.0.193-cc1"
EXPECTED_IMAGE_ID="sha256:f4804baf2825f1e4f58d021ab0378a3b8b5728fbe01ce28b31036c7788b739a4"
EXPECTED_TAR_SHA="c29d36858e52ef76244b2bcae169c4bde8995b83151f43d6f7e636b2c98c7cff"
EXPECTED_PATCH_SHA="40f531fcfd2c127e32d7da249b988ad12523644da1e820a06bb1d70526258660"
EXPECTED_VERSION="6.0.193"
TAR_NAME="cloudcamera-srs-6.0.193-cc1-linux-amd64.tar"
INSTALL_DIR="${INSTALL_DIR:-/opt/cloudcamera-srs/6.0.193-cc1}"
BACKUP_ROOT="${BACKUP_ROOT:-/root}"
MIN_FREE_GB="${MIN_FREE_GB:-20}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR=""

say()  { printf '%s\n' "$*"; }
pass() { printf 'PASS  %s\n' "$*"; }
warn() { printf 'WARN  %s\n' "$*"; }
fail() { printf 'FAIL  %s\n' "$*" >&2; }
die()  { fail "$*"; exit 1; }

[ "$(id -u)" -eq 0 ] || die "run as root (docker and /root backups)"

say "== 1. preflight =="
arch="$(uname -m)"
[ "$arch" = "x86_64" ] || die "unsupported architecture '$arch' (release is linux/amd64)"
pass "architecture $arch"

command -v docker >/dev/null 2>&1 || die "docker is not installed"
docker info >/dev/null 2>&1 || die "cannot talk to the docker daemon"
pass "docker $(docker version --format '{{.Server.Version}}')"
pass "hostname $(hostname)"

say ""
say "running containers:"
docker ps --format '  {{.Names}}  {{.Image}}  {{.Status}}' || true

say ""
say "host ports 1935/1985/8080/8000:"
ss -lntup 2>/dev/null | grep -E ':(1935|1985|8080)\b' || say "  (none listening)"

# ---------------------------------------------------------------------------
say ""
say "== 2. verify release archive =="
[ -f "$SCRIPT_DIR/$TAR_NAME" ] || die "missing $TAR_NAME next to this script"
actual_tar_sha="$(sha256sum "$SCRIPT_DIR/$TAR_NAME" | awk '{print $1}')"
[ "$actual_tar_sha" = "$EXPECTED_TAR_SHA" ] \
  || die "archive sha256 mismatch: $actual_tar_sha"
pass "archive sha256 $actual_tar_sha"

say ""
say "== 3. load image =="
docker load -i "$SCRIPT_DIR/$TAR_NAME"
actual_id="$(docker image inspect "$IMAGE_TAG" --format '{{.Id}}')"
[ "$actual_id" = "$EXPECTED_IMAGE_ID" ] || die "image id $actual_id != expected $EXPECTED_IMAGE_ID"
pass "image id $actual_id"

[ "$(docker image inspect "$IMAGE_TAG" --format '{{.Architecture}}/{{.Os}}')" = "amd64/linux" ] \
  || die "unexpected image platform"
pass "platform amd64/linux"

labels="$(docker image inspect "$IMAGE_TAG" --format '{{json .Config.Labels}}')"
printf '%s' "$labels" | grep -q "$EXPECTED_PATCH_SHA" || die "patch label missing"
printf '%s' "$labels" | grep -q '"org.cloudcamera.srs.channel":"cc1"' || die "channel label missing"
pass "labels channel=cc1 patch=$EXPECTED_PATCH_SHA"

version="$(docker run --rm --entrypoint ./objs/srs "$IMAGE_TAG" -v 2>&1 | tail -n1)"
case "$version" in
  *"$EXPECTED_VERSION"*) pass "srs -v $version" ;;
  *) die "unexpected srs version: $version" ;;
esac

# ---------------------------------------------------------------------------
say ""
say "== 4. back up current state =="
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$BACKUP_ROOT/srs-rollback-$STAMP"
mkdir -p "$BACKUP_DIR"

container="${SRS_CONTAINER:-}"
if [ -z "$container" ]; then
  mapfile -t candidates < <(docker ps --format '{{.Names}} {{.Image}}' | awk 'tolower($0) ~ /srs/ {print $1}')
  if [ "${#candidates[@]}" -eq 1 ]; then
    container="${candidates[0]}"
  elif [ "${#candidates[@]}" -gt 1 ]; then
    warn "several SRS-like containers found; set SRS_CONTAINER explicitly"
    printf '  %s\n' "${candidates[@]}"
  fi
fi

prev_image=""
prev_conf=""
if [ -n "$container" ] && docker inspect "$container" >/dev/null 2>&1; then
  docker inspect "$container" > "$BACKUP_DIR/container.json"
  prev_image="$(docker inspect "$container" --format '{{.Config.Image}}')"
  docker image inspect "$prev_image" > "$BACKUP_DIR/previous-image.json" 2>/dev/null || true
  prev_conf="$(docker inspect "$container" --format '{{range .Mounts}}{{if eq .Destination "/usr/local/srs/conf/srs.conf"}}{{.Source}}{{end}}{{end}}')"
  if [ -n "$prev_conf" ] && [ -f "$prev_conf" ]; then
    cp "$prev_conf" "$BACKUP_DIR/srs.conf.previous"
    pass "config backed up from $prev_conf"
  else
    warn "could not locate the mounted srs.conf for $container"
  fi
  pass "container $container (image $prev_image) recorded"
else
  warn "no running SRS container detected — nothing to back up on this node"
fi

cat > "$BACKUP_DIR/backup-meta.env" <<EOF
BACKUP_DIR=$BACKUP_DIR
BACKUP_TAKEN_AT=$STAMP
HOSTNAME=$(hostname)
PREV_CONTAINER=$container
PREV_IMAGE=$prev_image
PREV_CONF_SOURCE=$prev_conf
NEW_IMAGE=$IMAGE_TAG
NEW_IMAGE_ID=$actual_id
RELEASE_TAG=cc-v6.0.193-cc1
SOURCE_COMMIT=a6565e63c95cb2249f1808182e03f0cde782e77d
EOF
pass "backup metadata $BACKUP_DIR/backup-meta.env"

# ---------------------------------------------------------------------------
say ""
say "== 5. stage deployment files =="
mkdir -p "$INSTALL_DIR"
cp "$SCRIPT_DIR/docker-compose.uat.yml" "$INSTALL_DIR/docker-compose.yml"
cp "$SCRIPT_DIR/verify-ubuntu.sh" "$INSTALL_DIR/verify-ubuntu.sh"
cp "$SCRIPT_DIR/rollback-ubuntu.sh" "$INSTALL_DIR/rollback-ubuntu.sh"
cp "$SCRIPT_DIR/DEPLOYMENT-3-NODES.md" "$INSTALL_DIR/DEPLOYMENT-3-NODES.md"
chmod +x "$INSTALL_DIR/verify-ubuntu.sh" "$INSTALL_DIR/rollback-ubuntu.sh"
if [ ! -f "$INSTALL_DIR/srs.conf" ]; then
  cp "$SCRIPT_DIR/srs.conf.example" "$INSTALL_DIR/srs.conf"
  warn "staged srs.conf is the EXAMPLE — replace every <PLACEHOLDER> before deploying"
else
  warn "$INSTALL_DIR/srs.conf already exists — left untouched"
fi
pass "staged under $INSTALL_DIR"

# ---------------------------------------------------------------------------
say ""
say "== 6. disk headroom for the media volume =="
media="${CC_MEDIA_DIR:-}"
if [ -n "$media" ] && [ -d "$media" ]; then
  free_gb="$(df -BG --output=avail "$media" | tail -n1 | tr -dc '0-9')"
  if [ "${free_gb:-0}" -lt "$MIN_FREE_GB" ]; then
    warn "only ${free_gb}G free on $media (threshold ${MIN_FREE_GB}G) — do not deploy yet"
  else
    pass "${free_gb}G free on $media"
  fi
else
  warn "CC_MEDIA_DIR not set or missing — check the recorder mount manually"
fi

cat <<EOF

== ready for manual deployment (NOTHING was restarted) ==

1. Edit $INSTALL_DIR/srs.conf for this node (addresses, callback token, mounts,
   dvr path). http_remux stays inside the vhost block; keep hls_on_error ignore.
2. Validate:
     docker run --rm -v $INSTALL_DIR/srs.conf:/usr/local/srs/conf/srs.conf:ro \\
       $IMAGE_TAG ./objs/srs -t -c conf/srs.conf
3. Recreate the node's SRS container with the node's own compose/env values
   (CC_SRS_CONF, CC_MEDIA_DIR, ports and backend firewall rules).
4. Verify:  ./verify-ubuntu.sh
5. Rollback: ./rollback-ubuntu.sh --backup $BACKUP_DIR --compose <compose-file> --confirm
EOF
