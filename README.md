# pitato

Hardened Docker image for the [Pi coding agent](https://github.com/earendil-works/pi), pointed at one OpenAI-compatible endpoint. Includes `ripgrep` (apt) and `rtk` (built from source).

## Use

```sh
cp .env.example .env        # set PI_BASE_URL, PI_API_KEY, PI_MODEL (+ optional ALLOWED_DOMAINS)
mkdir -p workspace          # or set PROJECT_DIR=/path/to/project
docker compose build
docker compose run --rm pi
```

Extra args go to Pi: `docker compose run --rm pi -p "explain this repo"`.

## Working on any project: `pi-here`

Put `pi-here` on your PATH (e.g. `ln -s "$PWD/pi-here" ~/.local/bin/pi-here`), then from any project dir:

```sh
pi-here                       # mounts the current dir as /workspace
pi-here --root ~/code         # mounts ~/code; starts in the subdir you're in
pi-here --shell               # bash instead of Pi (works with --root)
pi-here --open                # unrestricted network (skips the egress proxy)
pi-here -h                    # help
```

Options must come before Pi's own args; the first unrecognised argument and everything after it goes to Pi.

It refuses to mount `/` or `$HOME`. Mounting a parent dir gives the agent write access to everything under it. It runs the container as your uid/gid, so files in the project stay owned by you.

## Egress allowlist

By default the container has no route to the internet. Its only way out is a Squid sidecar (`proxy/`) that allows the host in `PI_BASE_URL` plus anything in `ALLOWED_DOMAINS` (comma-separated, in `.env`; `.example.com` also matches subdomains). Everything else gets a 403. HTTPS is filtered by hostname on `CONNECT`, with no TLS interception.

```sh
ALLOWED_DOMAINS=github.com,.npmjs.org
```

- `pi-here` starts the proxy and recreates it when `.env` changes. It keeps running afterwards; stop it with `docker compose down`.
- `pi-here --open` skips the proxy and uses the normal open network.
- The allowlist is by hostname, not content: anything the agent can read can be sent to an allowed host.
- Plain `docker compose run --rm pi` also goes through the proxy and starts it if needed, but won't recreate a running proxy after you edit `.env`; use `docker compose up -d --wait proxy` for that. `docker compose run --rm pi-open` is the open equivalent.

## Built-in modes and commands

- **Plan mode** (Pi's example extension, loaded from the image): `/plan` or Ctrl+Alt+P toggles read-only exploration; `--plan` starts in it.
- **`/review [git range or focus]`**: reviews `git diff HEAD` plus untracked files (or the range you give) and reports findings by severity. Read-only by instruction only; the container is the real boundary.
- **Thinking level**: `/thinking`, or `pi-here --thinking high`. The model is declared as reasoning-capable; set `PI_REASONING=0` in `.env` for models that reject `reasoning_effort`. Whether the level changes behaviour depends on your server.

## What's in the image

| Tool | How | Pin |
|------|-----|-----|
| Pi | built from the release source archive with bun (as Pi's own release workflow does) | version + archive sha256 |
| rtk | `cargo build --release --locked` from git | tag + commit SHA |
| ripgrep, git | Debian apt | distro-signed |

The final stage has no compilers, curl or npm. Pi runs with `PI_OFFLINE=1`, version check and telemetry off.

## Upgrading

Edit the pinned `ARG`s at the top of `Dockerfile`:
- Pi: `PI_VERSION` and `PI_SOURCE_SHA256` (from the release's `SHA256SUMS`). Keep `BUN_VERSION` in line with Pi's `.github/workflows/build-binaries.yml`.
- rtk: `RTK_VERSION` and `RTK_COMMIT` (`git ls-remote https://github.com/rtk-ai/rtk <tag>`).

Adding a tool: add it to the `apt-get install` line, or add a builder stage and `COPY --from` its binary.

## Security model

- Non-root (uid 10001), read-only root fs, `cap_drop: ALL`, `no-new-privileges`, pid and memory limits.
- Persistent: `/workspace` and the `pi-data` named volume (`/home/pi/.pi`: Pi config and sessions). The rest of `/home/pi` and `/tmp` are tmpfs. `docker compose down -v` deletes the volume.
- `PI_API_KEY` may be blank for local models (a placeholder is used). A real key comes from runtime env only. It is not in the image, and `models.json` references `$PI_API_KEY` rather than containing it. It is also passed to the proxy container (it shares `.env`), and is visible to anyone with Docker access (`docker inspect`).
- Egress is limited to the model host plus `ALLOWED_DOMAINS` through the proxy sidecar (see above). The container sits on an internal network, so it cannot bypass the proxy. `pi-here --open` removes this restriction: the agent can then run arbitrary commands and reach any host.
- `rtk` is installed but not wired into Pi.
