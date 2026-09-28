# Mindful Machines Render Farm

Docker images for the Mindful Machines [Flamenco](https://flamenco.blender.org/) render farm. This repo builds three images:

- `ghcr.io/mindful-machines/render-farm-manager`: Flamenco Manager with `src/flamenco-manager.yaml` and the job types baked in.
- `ghcr.io/mindful-machines/render-farm-worker:5.2.2`: Blender, flamenco-worker, and Tailscale.
- `ghcr.io/mindful-machines/render-farm-sync:1.75.1`: rclone loop that copies pod frames from the RunPod volume to the share.

These images are meant to run on local machines as well as in the cloud on [RunPod GPUs](https://www.runpod.io/).

## How it fits together

- **Storage.** `\\media\blender\flamenco` (`B:\flamenco` on Windows) holds `project` and `renders`. Every container sees it at `/workspace/flamenco`: through a CIFS Docker volume on the manager and local workers, and through the network volume on pods. The RunPod volume holds a copy of `project`, and pod frames land in its `renders`.
- **Paths.** The two-way variable `storage` = `B:\flamenco` (Windows) / `/workspace/flamenco` (Linux). Submit jobs from Blender's Flamenco add-on (job type `blender-render-frames`); paths under `B:\flamenco` are converted to `{storage}/...`, so they resolve on any worker.
- **Network.** Local workers reach the Manager directly. Pods join the tailnet with userspace Tailscale and go through its HTTP proxy.
- **Frames from pods.** Pods write to the RunPod volume. The `flamenco-sync` container on the manager node copies them to the share every minute. Build the final video locally once every frame is on `B:`.

## How to Run

### Storage volume (manager and local workers, once per machine)

```sh
docker volume create --driver local --opt type=cifs \
  --opt device=//<nas-ip>/blender/flamenco \
  --opt o=addr=<nas-ip>,username=<user>,password=<pass>,vers=3.0 flamenco
```

Use an IP as Docker's CIFS mount doesn't resolve hostnames and Docker Desktop can't bind-mount mapped drives.

### Manager node

Linux with Docker, and Tailscale on the host so pods can reach it.

```sh
docker run -d --name flamenco-manager --restart unless-stopped -p 8080:8080 \
  -v flamenco-manager-data:/data -v flamenco:/workspace/flamenco \
  ghcr.io/mindful-machines/render-farm-manager:3.9.3
```

`docker ps` should show it `healthy`. Web UI: `http://<manager-host>:8080`.

### Worker node

Windows with Docker Desktop (WSL2 backend) and a current NVIDIA driver, or Linux with the NVIDIA Container Toolkit.

```sh
docker run -d --name flamenco-worker --restart unless-stopped --gpus all \
  -e MANAGER_URL=http://<manager-host>:8080/ -e WORKER_NAME=<machine-name> \
  -v flamenco:/workspace/flamenco \
  ghcr.io/mindful-machines/render-farm-worker:5.2.2
docker logs flamenco-worker | grep PREFS
```

The `PREFS` line shows the chosen backend with the GPU `True`:

- **OPTIX** on Linux hosts and RunPod.
- **CUDA** on Windows with Docker Desktop, whose WSL GPU passthrough doesn't provide OptiX. Rendering is ~5–12% slower, ~10–20% in total including loading. A native Windows `flamenco-worker.exe` (with `B:` mapped) keeps OptiX; the Manager's two-way `storage` variable already supports mixing Windows and Linux workers.
- **NONE** (no GPU): the worker exits instead of silently rendering on the CPU.

Stop the worker with `docker stop flamenco-worker`.

### Updating a node

After Actions has pushed a new image, pull it, remove the container and run the same `docker run` again:

```sh
docker pull <image> && docker rm -f <flamenco-manager|flamenco-worker|flamenco-sync>
```

### RunPod template

- GPU with 24 GB+ (RTX 4090, L40S, A6000).
- Network volume at `/workspace`.
- Container image: `ghcr.io/mindful-machines/render-farm-worker:5.2.2`. Leave the start command empty.
- Env: `MANAGER_URL=http://<manager-tailnet-name>:8080/`, and the secret `TS_AUTHKEY` (a reusable, ephemeral Tailscale auth key).
- Copy the project to the volume first (see Day to day).

### Render sync (manager node)

Pods can't reach the share, so `render-farm-sync` goes through the RunPod volume's S3 API. It copies new pod frames into the share every minute and skips frames that are still being written or already exist. Copy `.env.example` to `runpod.env` on the manager node and fill it in, then:

```sh
docker run -d --name flamenco-sync --restart unless-stopped --env-file runpod.env \
  -v flamenco:/workspace/flamenco ghcr.io/mindful-machines/render-farm-sync:1.75.1
```

## Day to day

```sh
git push                            # changes to Dockerfile or src/ → Actions builds all three images; then update the nodes
docker exec flamenco-sync farm-sync project   # after any .blend change, before pods render it: project → RunPod volume (copy, never deletes)
```

To upgrade Blender, Flamenco or Tailscale, bump the `ARG`s in `Dockerfile` and push. The version tag follows the `ARG`, so update the tag in the `docker run` commands and the RunPod template. If the Blender version changes, also update the Linux `blender` variable in `src/flamenco-manager.yaml`.

Manager API:

```sh
curl -s http://<manager-host>:8080/api/v3/worker-mgt/workers
curl -s http://<manager-host>:8080/api/v3/jobs
curl -s http://<manager-host>:8080/api/v3/jobs/<id>/tasks
curl -s http://<manager-host>:8080/api/v3/tasks/<id>/logtail
```

Final video, once all frames are on `B:`. Check first for gaps and zero-byte frames: with Overwrite off, Blender skips any frame file that exists, even a broken one.

```sh
ffmpeg -framerate 30 -i %06d.png -c:v libx264 -pix_fmt yuv420p -crf 16 out.mp4
```

## Known edge cases

- **A pod dies mid-chunk.** The chunk is requeued. If a local worker picks it up before `flamenco-sync` has copied the pod's finished frames, it re-renders them. That wastes GPU time only: `--ignore-existing` keeps the first copy, and with a fixed seed both copies are identical.
- **Dead pod workers.** Each pod registers as a new worker (`runpod-<pod id>`). Old ones stay listed as offline in the Manager; delete them from the web UI when convenient.
- **Mixed backends on one job.** CUDA (Docker Desktop) and OptiX (pods, Linux) trace rays slightly differently. With a fixed seed, frames should be practically identical but aren't guaranteed bit-exact. Spot-check neighbouring frames from each backend when a job is split between them.
- **Re-pushing the same version.** A build without an `ARG` bump overwrites the version tag. Pin `:sha-<commit>` when you need an exact build.

## Agent tooling

`apm install && apm compile` generates `.claude/` and `.mcp.json` (gitignored) from `apm.yml`. The Firecrawl MCP server needs `FIRECRAWL_API_KEY`.
