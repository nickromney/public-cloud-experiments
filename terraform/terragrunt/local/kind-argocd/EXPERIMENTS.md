# CI Build Experiments (host-side Gitea Actions + DinD)

## Current Recommendation

**Use direct host builds via `make local kind prereqs`** instead of Gitea Actions with DinD. The DinD approach on Podman/macOS has fundamental issues with storage drivers and resource usage that make it unreliable for this use case.

## What we tried

### Phase 1: HTTP Registry + DinD
- External Gitea with registry over HTTP (`ROOT_URL=http://host.docker.internal:30090/`, container packages enabled).
- Host-runner using `gitea/act_runner:0.2.13` + DinD (`docker:dind`) on `tcp://host.docker.internal:23750`.
- Runner labels include `ubuntu-latest:docker://ghcr.io/catthehacker/ubuntu:act-latest`; buildx driver `docker`; binfmt installed.
- Workflow tweaks:
  - Registry host `host.docker.internal:30090`, docker/login `insecure: true`.
  - Buildx driver docker; frontend build uses `NODE_OPTIONS=--max-old-space-size=1024`.
  - Removed HTTPS schemes from tags; attempted `registry.insecure=true` outputs.
- DinD config via `/etc/docker/daemon.json` with `"insecure-registries": ["host.docker.internal:30090"]`.

### Phase 2: HTTPS Registry + Self-Signed CA (December 2024)
- Switched Gitea registry to HTTPS with self-signed CA (`certs/ca.crt`).
- Mounted CA into DinD, runner, and workflow containers.
- Added CA trust to workflow steps via `update-ca-certificates`.

## Issues observed

### Phase 1 Issues
- buildx pushes still attempted HTTPS, yielding `http: server gave HTTP response to HTTPS client` when pushing to the registry.
- Frontend build occasionally hit `lfstack.push`/OOM in `npm run build` (node:22-alpine).
- DinD warnings when both flag and daemon.json specified insecure registries; avoided by using daemon.json only.
- Action logs from later runs sometimes not persisted in `actions_log` after wiping Gitea data (DB reseeded; runner still fetched tasks).

### Phase 2 Issues (DinD on Podman/macOS - Apple Silicon)

1. **unpigz corruption**: `failed to register layer: exit status 1: unpigz: skipping: <stdin>: corrupted -- incomplete deflate data` when pulling large images (e.g., `mcr.microsoft.com/azure-functions/python:4-python3.11`).

2. **VFS storage driver xattr issues**: `failed to register layer: lgetxattr security.capability ... no such file or directory` - VFS driver doesn't properly support extended attributes on Podman's virtiofs.

3. **Overlay2 storage driver failures**: `error initializing graphdriver: error changing permissions on file for metacopy check: chmod ... network dropped connection on reset: overlay2` - overlay2 fails during initialization.

4. **containerd mount failures**: `failed to create container: mount callback failed on /tmp/containerd-mount...: network dropped connection on reset` - nested container creation fails.

5. **tmpfs workaround causes memory pressure**: Using `--tmpfs /var/lib/docker:size=20g` avoids virtiofs issues but puts significant memory pressure on the host, causing Gitea to become unresponsive (29-second SQL queries, 500 errors).

6. **SSH known_hosts hostname mismatch**: Workflow runs inside containers connect to `host.docker.internal:30022`, but known_hosts generated from host only had entries for `127.0.0.1:30022`. Fixed by adding both hostnames to known_hosts.

7. **ARM64 platform mismatch**: Mac Apple Silicon pulls ARM64 images by default, but `mcr.microsoft.com/azure-functions/python` only has AMD64. Fixed with `--platform linux/amd64` on docker pull commands.

## What worked

- HTTPS with self-signed CA: Registry push/pull works when CA is properly trusted.
- tmpfs for `/var/lib/docker`: Avoids virtiofs xattr/overlay issues (overlayfs works in tmpfs).
- Pre-pull with retry and platform specification: `--platform linux/amd64` fixes ARM64 mismatch.
- Dual-hostname known_hosts: Adding both `127.0.0.1` and `host.docker.internal` entries.
- `pull: false` in buildx: Uses pre-pulled images instead of re-pulling during build.

## Conclusion

DinD inside Podman on macOS (Apple Silicon) is fundamentally problematic:
- Storage drivers that work on Linux (overlay2) fail due to virtiofs limitations.
- VFS works but has xattr issues with certain images.
- tmpfs workaround uses excessive memory.
- Resource contention causes Gitea database slowdowns.

**Recommended approach**: Build images directly on the host with `make local kind prereqs` and push to the registry, bypassing Gitea Actions/DinD entirely. This is simpler, faster, and more reliable.

## Files modified during DinD experiments

- `scripts/stage200-build.sh`: DinD setup, pre-pull with retry, tmpfs configuration
- `gitea-repos/azure-auth-sim/.gitea/workflows/azure-auth-sim.yaml`: Pre-pull step, platform flags, pull:false
- `.run/gitea_known_hosts`: Added `host.docker.internal` entries
