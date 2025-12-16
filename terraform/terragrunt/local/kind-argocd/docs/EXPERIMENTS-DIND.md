# DinD Experiments (Gitea Actions runner)

Summary of attempts to run the Gitea Actions runner with a Docker-in-Docker (DinD) daemon for building/pushing images.

## Drivers tried

- overlay2 (default in docker:dind): frequent mount errors and shim disconnects (`mount callback failed on /tmp/containerd-mount...`, `network dropped connection on reset`). Layer pulls occasionally succeeded; build container creation often failed.
- fuse-overlayfs: docker daemon still reported `overlayfs`; instability persisted; corrupt layer errors remained.
- vfs (forced): pulls failed with `failed to register layer: lgetxattr security.capability ... /etc/alternatives/awk: no such file or directory` even with retries.

## Mitigations attempted

- Disabled pigz (`DOCKER_BUILDX_DISABLE_PIGZ=1`).
- Increased `/tmp` tmpfs to 4G.
- Cleaned data dir between runs; removed DinD+runner containers between stage 200 runs.
- Pre-pull with retry for base images (act-latest, Azure Functions python base, uv, node:22-alpine, nginx:alpine).
- Pinned storage driver via `--storage-driver` flag.
- Added hello-world sanity check.

## Observed errors

- Mount callback failures during container create: `open /tmp/containerd-mount.../dev/console: network dropped connection on reset`.
- Layer registration failures: `unpigz: corrupted -- incomplete deflate data` on Azure Functions base; `lgetxattr security.capability ... no such file or directory` on vfs.
- Context-canceled writes during layer pulls with overlayfs.

## Conclusion

DinD inside the current Podman/KinD environment remained unstable across storage drivers. Recommend pivoting to using the host Podman/Buildx socket directly from the runner (no inner dockerd) to avoid nested daemon issues.
