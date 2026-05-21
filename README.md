# devcontainer-setup

A drop-in `.devcontainer/` template for projects that want to give Claude Code a sandboxed development environment with a strict outbound firewall.

## What's in the box

| File | Purpose |
| --- | --- |
| `Dockerfile` | Debian 13 slim base + the minimum packages needed (`curl`, `git`, `zsh`, `sudo`, `iptables`, `ipset`, `aggregate`, `ca-certificates`). Creates the non-root `dev` user. |
| `docker-compose.yml` | Defines the `devcontainer` service. Add your own services (DBs, queues) alongside it. |
| `devcontainer.json` | Wires the dev container to compose. Configures features (`common-utils`, `node`, `java`, `claude`). Runs `init-firewall.sh` on every container start. |
| `init-firewall.sh` | Sets the container's egress firewall to a deny-by-default policy with an allowlist. Also installs localhost → service-name DNAT rules so the dev container can talk to sibling compose services via `localhost:<port>`. |
| `allowed-domains.conf` | Plain-text list of hostnames that the firewall should resolve and allow. |
| `start.sh` | Bootstraps the dev container: installs `@devcontainers/cli` locally into the project's `node_modules/` if missing, builds + starts the stack, then launches Claude inside. |
| `attach.sh` | Fast path that skips the build and attaches Claude to an already-running dev container. |

## Why use this

- **Network containment.** Claude (and anything else inside the container) can only reach the hosts you've explicitly listed in `allowed-domains.conf`, plus GitHub's dynamic CIDR ranges and the compose internal network. Useful when running coding agents with elevated permissions.
- **No host pollution.** Your project's runtime (JDK, Node, tooling) lives in the image, not on your laptop.
- **Service-hostname parity with the host.** The compose stack publishes service ports to the host. The DNAT rules in `init-firewall.sh` make those same ports work as `localhost:<port>` from *inside* the dev container too. The same `application.yml` / config file works in both environments.

## Prerequisites

- Docker (Docker Desktop, OrbStack, or anything that provides a working `docker compose` and supports the `sysctls` directive).
- Node.js — only because `start.sh` will run `npm install @devcontainers/cli` into the project's `node_modules/` if the local binary isn't already present. No global install, no `sudo`. If you provide the CLI another way, Node is not required.
- An `ANTHROPIC_API_KEY` (or a Claude login session) on first run.

## Quick start in an existing project

1. From your project root, run the installer to pull the latest `.devcontainer/` from this repo:
   ```bash
   curl -fsSL https://raw.githubusercontent.com/MairoldCB/devcontainer-setup/main/install.sh | bash
   ```
   (Or copy the `.devcontainer/` directory manually if you'd rather pin a specific version.)
2. Open `.devcontainer/devcontainer.json` and set:
   - `"name"` — anything; shows up in IDE UIs.
   - `forwardPorts` + `portsAttributes` — list the host ports your app needs IDE-side forwarding for (e.g. backend on 4040, frontend on 8080).
   - `remoteEnv` — environment variables to forward from your shell into the container.
   - `features` — only `common-utils` and `claude` are active by default. `node` and `java` are included as commented-out examples; uncomment them if your project needs them, or remove the lines entirely. Browse the official catalog at [containers.dev/features](https://containers.dev/features) to pull in additional dependencies (Python, Go, Rust, AWS CLI, Docker-in-Docker, etc.) — copy the `ghcr.io/...` reference into the `features` block. The `overrideFeatureInstallOrder` block makes sure `common-utils` runs first so things like `sudo` and `ca-certificates` exist before later features try to use them.
3. Open `.devcontainer/docker-compose.yml` and:
   - Set the top-level `name:` to your project name.
   - Add your project's services (Postgres, Redis, MQTT, etc.) alongside the `devcontainer` service. For anything you add, give it a `healthcheck:` block and add a corresponding entry to the `devcontainer` service's `depends_on:` so the dev container only starts once your dependencies are ready:
     ```yaml
     devcontainer:
       # ...
       depends_on:
         db:
           condition: service_healthy
         mqtt:
           condition: service_healthy
     ```
     Without this, `init-firewall.sh`'s `PORT_FORWARDS` step can't resolve service hostnames yet, and your app may race the DB on startup.
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

The first run creates `node_modules/`, `package.json`, and `package-lock.json` in your project root (from the local `@devcontainers/cli` install). Add them to your `.gitignore` if you don't want them tracked.

## Running parallel sessions with worktrees

Both `start.sh` and `attach.sh` accept an optional first argument that's forwarded as Claude's [`--worktree`](https://code.claude.com/docs/en/worktrees) flag. Each named worktree is an isolated git working directory + branch (`worktree-<name>`) created under `.claude/worktrees/<name>/`, so two parallel Claude sessions can work on different things without stepping on each other's files.

```bash
# First session
./.devcontainer/start.sh feature-auth      # creates worktree-feature-auth

# Second session, in another terminal
./.devcontainer/attach.sh bugfix-123       # creates worktree-bugfix-123
```

Without an argument, both scripts launch Claude in the main workspace as before.

Notes:

- The first time you use `--worktree` in a project, Claude needs the workspace trust dialog accepted. Run `./.devcontainer/attach.sh` once without an argument first to clear it.
- Add `.claude/worktrees/` to your project's `.gitignore` so worktree directories don't appear as untracked files.
- If your project has gitignored files that worktrees still need (`.env`, `.env.local`, etc.), list them in a `.worktreeinclude` file at the project root — Claude will copy them into each new worktree.
- See the [Claude Code worktree docs](https://code.claude.com/docs/en/worktrees) for cleanup behavior, PR-based worktrees (`./.devcontainer/start.sh "#1234"`), and subagent isolation.

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

