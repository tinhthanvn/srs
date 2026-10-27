# Deploying `cloudcamera-srs:6.0.193-cc1` to three Ubuntu streaming nodes

Owner-executed runbook. Nothing in this document is applied automatically; each node is
deployed and verified **sequentially**: Node 1 → verify → Node 2 → verify → Node 3 → verify.
Never restart all nodes at once.

## 0. Release artifact

Use the archive shipped with the release (do not build on the node):

```
cloudcamera-srs-6.0.193-cc1-linux-amd64.tar
cloudcamera-srs-6.0.193-cc1-linux-amd64.tar.sha256
```

Verify locally before upload:

```bash
sha256sum -c cloudcamera-srs-6.0.193-cc1-linux-amd64.tar.sha256
```

## 1. Per-node preflight (read-only)

Run on the node, record the output in the worksheet.

```bash
hostname
uname -m                                  # expect x86_64
docker version --format '{{.Server.Version}}'
docker ps --format '{{.Names}}\t{{.Image}}\t{{.Status}}'
df -h /var/lib/docker /srv /data 2>/dev/null
docker inspect <current-srs-container> --format '{{json .Mounts}}'
ss -lntup | grep -E ':(1935|1985|8080|8000)\b'
curl -s http://127.0.0.1:1985/api/v1/versions
curl -s http://127.0.0.1:1985/api/v1/streams/?count=200
```

Stop if:

- architecture is not `x86_64`;
- the media/DVR mount is missing or the free space is below the recording budget;
- the current publisher inventory is not recorded (needed to prove recovery);
- the node runs another project's SRS container.

## 2. Back up the node

```bash
mkdir -p /root/srs-rollback-$(date +%Y%m%d)
docker inspect <container> > /root/srs-rollback-*/container.json
cp <current-srs.conf> /root/srs-rollback-*/srs.conf
cp <current-compose.yml> /root/srs-rollback-*/compose.yml
docker image inspect <current-image> > /root/srs-rollback-*/image.json
# Optional, when the running image is a previous custom build:
docker save -o /root/srs-rollback-*/previous-image.tar <current-image>
```

Keep the previous image tag on the node. Do not delete it until the new node is accepted.

## 3. Load and verify the image

```bash
sha256sum -c cloudcamera-srs-6.0.193-cc1-linux-amd64.tar.sha256
docker load -i cloudcamera-srs-6.0.193-cc1-linux-amd64.tar
docker image inspect cloudcamera-srs:6.0.193-cc1 \
  --format '{{.Id}} {{.Architecture}} {{json .Config.Labels}}'
docker run --rm --entrypoint sh cloudcamera-srs:6.0.193-cc1 -c '/usr/local/srs/objs/srs -v'
```

Expected: architecture `amd64`, version `6.0.193`, labels `channel=cc1`,
`patch.sha256=40f531…`, `upstream.commit=aab043c7…`. The image ID must equal the ID recorded
in the release manifest.

## 4. Prepare the node configuration (node-specific)

Start from the release `srs.conf.example` and set the node's own values. Never copy another
node's IP addresses, callback host, storage mounts or ports.

Required in the **vhost** block (not in `http_server`):

```
http_remux {
    enabled on;
    mount [vhost]/[app]/[stream].flv;
    fast_cache 0;
}
```

Required for self-healing:

```
hls {
    ...
    hls_on_error ignore;
}
```

Also preserve, per node:

- `http_hooks` callback base and the **per-node** callback token (never the shared legacy token);
- `dvr_path` and the recorder mount used by the backend uploader;
- HLS paths/templates expected by the backend node registry (`PUBLIC_HLS_BASE`);
- `http_api`/`http_server` ports mapped to the host ports the backend registry records.

Before any restart, validate the config (SRS config test, or start the image once with
`-t`/`--check` where supported and inspect the exit code):

```bash
docker run --rm -v "$PWD/srs.conf:/usr/local/srs/conf/srs.conf:ro" \
  cloudcamera-srs:6.0.193-cc1 ./objs/srs -t -c conf/srs.conf
```

## 5. Deploy

```bash
docker compose -f docker-compose.node.yml up -d
docker ps --filter name=<container>
docker logs --since 2m <container> | tail -50
```

Use the node's existing container name, ports, mounts and restart policy. Do not introduce a
new public port.

## 6. Post-start verification

| Check | Command / criterion |
| --- | --- |
| API up | `curl -s http://127.0.0.1:1985/api/v1/versions` |
| Publishers recovered | `curl -s http://127.0.0.1:1985/api/v1/streams/?count=200` — same camera streams as the preflight |
| HLS | `curl -s http://127.0.0.1:8080/<app>/<stream>/<stream>.m3u8` — `#EXTM3U`, MEDIA-SEQUENCE advancing |
| HTTP-FLV origin | `curl -s -m 3 -o /dev/null -w '%{http_code} %{content_type}\n' http://127.0.0.1:8080/<app>/<stream>.flv` — `200 video/x-flv` |
| DVR | a new segment appears under `dvr_path` within one segment interval and is non-zero |
| Reconnect | restart one publisher; stream returns without restarting SRS |
| Self-heal | (maintenance window) break one stream's HLS output directory and confirm the `hls: self-heal scheduled` / `rebuilt after N failed attempt(s)` log lines while other streams keep advancing |
| Gateway | browser playback only through the application `/media/live/{ticket}` path; never hand the raw origin to clients |

The origin HTTP port and the management API must be reachable only by the backend and the
operator network. `1985` must never be public. Restrict `8080` to the backend/allowlist; the
browser path is the authenticated gateway.

## 7. Rollback

Per node, in this order:

```bash
docker compose -f docker-compose.node.yml down
cp /root/srs-rollback-*/srs.conf <current-srs.conf>
cp /root/srs-rollback-*/compose.yml <current-compose.yml>
# previous image tag is already present locally (or: docker load -i previous-image.tar)
docker compose -f docker-compose.node.yml up -d
```

Verify publishers, HLS and DVR as in §6. Record the rollback reason.

## 8. Per-node worksheet

| Field | Node 1 | Node 2 | Node 3 |
| --- | --- | --- | --- |
| Hostname | | | |
| Architecture (`uname -m`) | | | |
| Docker version | | | |
| SRS container / image before | | | |
| Host ports (RTMP/API/HTTP) | | | |
| Media mount / free space | | | |
| Publishers before | | | |
| Config backup path | | | |
| Image ID after load | | | |
| Publishers after | | | |
| HLS / FLV / DVR result | | | |
| Rollback needed (Y/N) | | | |
| Notes | | | |

## 9. Safety rules

- Sequential rollout only; never restart all three nodes together.
- Do not change S3/NAS credentials, lifecycle rules or retention as part of the SRS rollout.
- Do not delete the local DVR spool to make room; fix capacity first.
- Do not overwrite the official `ossrs/srs:v6.0-r2` tag.
- Do not reuse a configuration file across nodes without checking every address, token and mount.
