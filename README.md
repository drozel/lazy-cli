# lazy-cli

A Zsh plugin providing fzf-powered keyboard shortcuts for Docker Swarm and shell productivity.

## Overview

### Multi-node container exec (ctrl+w)

The main feature is `ctrl+w`: a two-step fzf picker that finds and execs into containers across all nodes of a Swarm cluster — no SSH, no manual context switching.

Managing Docker Swarm clusters typically requires SSH-ing into multiple nodes to find where a specific container is running. lazy-cli automates this:

- [Docker Contexts](https://docs.docker.com/engine/manage-resources/contexts/) configured for your cluster
- Contexts named with a namespace pattern: `my-system.1`, `my-system.2`, ..., `my-system.N` (one per Swarm node)
- Switch to any context in the namespace — `ctrl+w` searches the rest automatically

**Before lazy-cli:**

```bash
ssh my-system-node-1.mycompany.com
docker ps | grep my-container  # not here
ssh my-system-node-2.mycompany.com
docker ps | grep my-container  # not here
ssh my-system-node-3.mycompany.com
docker ps | grep my-container  # finally here!
docker exec -it <container_id> bash
```

**With lazy-cli:**

Press `ctrl+w`, pick the service, pick the container — done.

1. **Service picker** — lists all Swarm services in the current context
2. **Container picker** — finds matching containers across every node in the namespace; navigate with arrow keys, then:

| Key | Action |
|-----|--------|
| `e` or Enter | `docker exec -it <container> bash` |
| `i` | `docker inspect <container>` |
| `l` | `docker logs -f <container>` |

The command is placed in your prompt buffer so you can review or edit it before running.

### All keyboard shortcuts

| Shortcut | Description |
|----------|-------------|
| `ctrl+h` | Toggle a cheatsheet of all shortcuts |
| `ctrl+x` | Pick a Docker context (session-local, colima first) |
| `ctrl+w` | Pick a Swarm service → container across nodes → exec / inspect / logs |
| `ctrl+e` | Pick a running container and exec into it (current context only) |
| `ctrl+l` | Pick a running container and tail its logs |
| `esc+L`  | Pick a Docker Swarm service and tail its logs |
| `ctrl+b` | Git branch picker sorted by most recent commit |
| `ctrl+g` | Git log browser with diff preview |
| `ctrl+t` | Taskfile task picker |

> `ctrl+l` overrides the default clear-screen binding. Use `reset` or `clear` instead.

## Utilities

Two shell functions are available for scripting and bulk operations:

| Command | Description |
|---------|-------------|
| `dlazy-foreach-svc <filter> <action>` | Run a `docker service` action against all services matching the filter |
| `docker-context-unset` | Unset the session-local `DOCKER_CONTEXT` override and fall back to the system-wide context |

### Bulk service actions

```zsh
dlazy-foreach-svc database rm
# Executes 'docker service rm' for each service with "database" in its name
```

## Installation

### Using Zinit

Add the following to your `~/.zshrc`:

```zsh
zinit light drozel/lazy-cli
```

Then reload your shell:

```zsh
source ~/.zshrc
```

### Using Oh-My-Zsh

1. Clone this repository into Oh-My-Zsh's plugins directory:

```zsh
git clone https://github.com/drozel/lazy-cli.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/lazy-cli
```

2. Add `lazy-cli` to the plugins array in your `~/.zshrc`:

```zsh
plugins=(... lazy-cli)
```

3. Reload your shell:

```zsh
source ~/.zshrc
```

### Manual Installation

```zsh
git clone https://github.com/drozel/lazy-cli.git ~/.lazy-cli
echo "source ~/.lazy-cli/dockerlazy.plugin.zsh" >> ~/.zshrc
source ~/.zshrc
```

## Requirements

- Docker CLI with contexts configured (namespace pattern `cluster.1`, `cluster.2`, … for multi-node features)
- Zsh
- [fzf](https://github.com/junegunn/fzf)
- [Task](https://taskfile.dev) — optional, for `ctrl+t`

## License

MIT
