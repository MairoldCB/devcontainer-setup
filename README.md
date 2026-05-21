# devcontainer-setup

A drop-in `.devcontainer/` template for projects that want to give [Claude Code](https://claude.com/claude-code) a sandboxed development environment with a strict outbound firewall.

## What's in the box

| File | Purpose |
| --- | --- |
| `Dockerfile` | Debian 13 slim base + the minimum packages needed (`curl`, `git`, `zsh`, `sudo`, `iptables`, `ipset`, `aggregate`, `ca-certificates`). Creates the non-root `dev` user. |
| `docker-compose.yml` | Defines the `devcontainer` service. Add your own services (DBs, queues) alongside it. |
| `devcontainer.json` | Wires the dev container to compose. Configures features (`common-utils`, `node`, `java`, `claude`). Runs `init-firewall.sh` on every container start. |
| `init-firewall.sh` | Sets the container's egress firewall to a deny-by-default policy with an allowlist. Also installs localhost → service-name DNAT rules so the dev container can talk to sibling compose services via `localhost:<port>`. |
| `allowed-domains.conf` | Plain-text list of hostnames that the firewall should resolve and allow. |
| `start.sh` | Bootstraps the dev container: installs `@devcontainers/cli` if missing, builds + starts the stack, then launches Claude inside. |
| `attach.sh` | Fast path that skips the build and attaches Claude to an already-running dev container. |

## Why use this

- **Network containment.** Claude (and anything else inside the container) can only reach the hosts you've explicitly listed in `allowed-domains.conf`, plus GitHub's dynamic CIDR ranges and the compose internal network. Useful when running coding agents with elevated permissions.
- **No host pollution.** Your project's runtime (JDK, Node, tooling) lives in the image, not on your laptop.
- **Service-hostname parity with the host.** The compose stack publishes service ports to the host. The DNAT rules in `init-firewall.sh` make those same ports work as `localhost:<port>` from *inside* the dev container too. The same `application.yml` / config file works in both environments.

## Prerequisites

- Docker (Docker Desktop, OrbStack, or anything that provides a working `docker compose` and supports the `sysctls` directive).
- Node.js — only because `start.sh` will `npm install -g @devcontainers/cli` if the CLI isn't already on `PATH`. If you install the CLI another way, Node is not required.
- An `ANTHROPIC_API_KEY` (or a Claude login session) on first run.

## Quick start in an existing project

1. Copy this `.devcontainer/` directory to the root of your project.
2. Open `.devcontainer/devcontainer.json` and set:
   - `"name"` — anything; shows up in IDE UIs.
   - `forwardPorts` + `portsAttributes` — list the host ports your app needs IDE-side forwarding for (e.g. backend on 4040, frontend on 8080).
   - `remoteEnv` — environment variables to forward from your shell into the container.
   - `features` — keep `claude`; add/remove language features as needed. Stack-agnostic features in this template: `common-utils`, `node`, `java`. Browse the official catalog at [containers.dev/features](https://containers.dev/features) to pull in additional dependencies (Python, Go, Rust, AWS CLI, Docker-in-Docker, etc.) — copy the `ghcr.io/...` reference into the `features` block. The `overrideFeatureInstallOrder` block makes sure `common-utils` runs first so things like `sudo` and `ca-certificates` exist before later features try to use them.
3. Open `.devcontainer/docker-compose.yml` and:
   - Set the top-level `name:` to your project name.
   - Add your project's services (Postgres, Redis, MQTT, etc.) alongside the `devcontainer` service.
   - Mount any cache volumes your toolchain needs (Maven `~/.m2`, Gradle `~/.gradle`, npm cache).
4. Open `.devcontainer/allowed-domains.conf` and append the hostnames your build/runtime needs (your APIs, registries, cloud providers, etc.). One per line; lines starting with `#` are comments.
5. If your app expects to reach sibling compose services on `localhost:<port>` (same as on the host), add them to the `PORT_FORWARDS` array in `init-firewall.sh`:
   ```bash
   PORT_FORWARDS=(
       "5433 db 5432"
       "1883 mqtt 1883"
   )
   ```
   Format: `"<localhost-port> <compose-service-name> <service-internal-port>"`. Without this, the dev container can still reach services by hostname (e.g. `db:5432`), but `localhost:5433` won't work from inside.
6. Run `./.devcontainer/start.sh` from the project root.

On subsequent sessions, run `./.devcontainer/attach.sh` instead — it skips the rebuild and attaches Claude in a few seconds.

## How the firewall works

`init-firewall.sh` runs on every container start via `postStartCommand`. It:

1. Preserves Docker's internal DNS rules (so `getent hosts <service-name>` still works).
2. Creates an `ipset` called `allowed-domains` and populates it from:
   - GitHub's published CIDR ranges (via `https://api.github.com/meta`).
   - Each hostname in `allowed-domains.conf`, resolved at boot via `dig`.
3. Allows traffic to the host's `/24` and Docker's internal `172.x.x.x/16` networks (otherwise compose service-to-service traffic would be blocked).
4. Optionally installs localhost-DNAT rules from `PORT_FORWARDS`.
5. Sets default policies to `DROP` and `REJECT`s anything not matching an allow rule.
6. Verifies the policy by curling `example.com` (should fail) and `api.github.com` (should succeed). The container fails to start if either check is wrong.

Because the allowlist resolves at boot, hostnames that rotate IPs frequently (CDNs especially) may break — refresh by restarting the container.

### `route_localnet` sysctl

The `docker-compose.yml` sets `net.ipv4.conf.all.route_localnet=1`. This is required for the localhost-DNAT trick to work — Linux ignores NAT rules on `127.0.0.0/8` traffic by default. The sysctl is "namespaced", so it only affects this container's network namespace.

## Customization tips

- **Different base image.** Change the `FROM` line in `Dockerfile`. If you move off Debian, also update the `apt-get` line.
- **Don't want the firewall.** Remove the `postStartCommand` from `devcontainer.json` and drop `iptables`/`ipset`/`aggregate` from the `Dockerfile` apt list. Note that you also lose the localhost-DNAT feature.
- **Need root inside the container.** The `dev` user has passwordless sudo only for `/usr/local/bin/init-firewall.sh`. For broader sudo, change the `sudoers.d` rule in the `Dockerfile`.
- **Persistent shell history / Claude state.** Already wired via named volumes `claude-config`, `claude-json`, `claude-history`.

## JetBrains Gateway caveat

Gateway's devcontainer engine does **not** currently honor `overrideFeatureInstallOrder` ([IDEA-334532](https://youtrack.jetbrains.com/issue/IDEA-334532)). If you open this devcontainer via Gateway directly, you'll see feature install failures because features run in a non-deterministic order. Workarounds:

- Run `start.sh` first (uses the official `@devcontainers/cli`, which respects ordering), then attach Gateway to the **running container** instead of letting it build.
- Or, make your features self-bootstrapping — have each `install.sh` install its own apt prerequisites — so order doesn't matter.

## Troubleshooting

| Symptom | Likely cause |
| --- | --- |
| `claude: command not found` after start | The claude feature's `~/.local/bin` is on `PATH` only via `remoteEnv` in `devcontainer.json`. Make sure that block is intact. |
| `Connection timed out` to `localhost:<port>` from inside the container | The `PORT_FORWARDS` entry for that port is missing, or the `route_localnet` sysctl didn't apply. Check `docker-compose.yml` and re-run `start.sh`. |
| `Firewall verification failed - was able to reach https://example.com` | A previous run's iptables rules weren't flushed properly. Restart the dev container. |
| Feature install fails with `error setting certificate file: /etc/ssl/certs/ca-certificates.crt` | `ca-certificates` is missing from the base image — keep it in the Dockerfile apt list. |
| Feature install fails with `su: failed to execute /bin/zsh` | `zsh` is missing — keep it in the apt list (the `dev` user is created with zsh as its login shell). |
| Feature install fails with `cannot create /etc/sudoers.d/...` | `sudo` is missing — keep it in the apt list. |

## License

Use it however you like. Attribution appreciated but not required.
