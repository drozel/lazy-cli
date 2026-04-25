# lazy-cli

A collection of powerful helper functions for Docker CLI and shell productivity, designed to simplify managing Docker Swarm clusters across multiple contexts.

## Overview

### Multi-node Context Switching

The killer feature is automatic context switching between Docker Swarm nodes while searching for containers.

Managing Docker Swarm clusters typically requires SSH-ing into multiple nodes to find where a specific container is running. lazy-cli automates this tedious process. All you need is:

- [Docker Contexts](https://docs.docker.com/engine/manage-resources/contexts/) configured for your cluster
- Multiple contexts named with a namespace pattern: `my-system.1`, `my-system.2`, ..., `my-system.N` (where each represents a Swarm node)
- Switch to any context in the namespace to start operating with the entire cluster

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

```bash
dlazy-exec my-container
```

lazy-cli automatically searches across all nodes in the namespace, switches to the correct context, and executes a shell inside the container.

### fzf Keyboard Shortcuts

lazy-cli also provides a set of interactive fzf-powered widgets bound to keyboard shortcuts:

| Shortcut | Description |
|----------|-------------|
| `ctrl+h` | Toggle a cheatsheet of all shortcuts |
| `ctrl+x` | Pick a Docker context (session-local, colima first) |
| `ctrl+e` | Pick a running container and exec into it |
| `ctrl+l` | Pick a running container and tail its logs |
| `esc+L`  | Pick a Docker Swarm service and tail its logs |
| `ctrl+b` | Git branch picker sorted by most recent commit |
| `ctrl+g` | Git log browser with diff preview |
| `ctrl+t` | Taskfile task picker |

> `ctrl+l` overrides the default clear-screen binding. Use `reset` or `clear` instead.

## Commands

| Command | Description |
|---------|-------------|
| `dlazy-help` | Display help information and usage examples |
| `dlazy-find <container_name>` | Find container(s) by name in the current context (supports partial matching) |
| `dlazy-find-in-cluster <container_name>` | Search for a container across all contexts in the namespace and switch to the correct node |
| `dlazy-exec <container_name>` | Execute bash (or sh as fallback) in a container by name, automatically finding it across cluster nodes |
| `dlazy-foreach-svc <filter> <action>` | Execute an action on all Docker services matching the filter |
| `docker-context-unset` | Unset the session-local `DOCKER_CONTEXT` override and fall back to the system-wide context |

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

Clone this repository and source the plugin file in your `~/.zshrc`:

```zsh
git clone https://github.com/drozel/lazy-cli.git ~/.lazy-cli
echo "source ~/.lazy-cli/dockerlazy.plugin.zsh" >> ~/.zshrc
source ~/.zshrc
```

## Usage Examples

### Find a container by name

```zsh
dlazy-find myapp
# Returns container ID(s) matching "myapp" in the current context
```

### Find a container across cluster contexts

```zsh
dlazy-find-in-cluster web-server
# Searches all nodes and switches to the context where the container is running
```

### Execute a shell in a container

```zsh
dlazy-exec myapp
# Finds the container across all nodes and opens an interactive shell
```

### Perform bulk actions on services

```zsh
dlazy-foreach-svc database rm
# Executes 'docker service rm' for each service with "database" in its name
```

## Requirements

- Docker CLI installed and configured
- Zsh shell
- [fzf](https://github.com/junegunn/fzf) — required for keyboard shortcut widgets
- Docker contexts set up with namespace pattern (e.g., `cluster.1`, `cluster.2`) for multi-node operations
- [Task](https://taskfile.dev) — optional, required for `ctrl+t` task picker

## License

MIT
