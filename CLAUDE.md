# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository

GitHub: `drozel/lazy-cli` — a Zsh plugin that provides Docker Swarm helper functions and fzf-powered keyboard widgets.

## Testing

There is no build system or test suite. To validate changes, source the plugin directly in a Zsh session:

```zsh
source lazy-cli.plugin.zsh
```

Then exercise the affected functions or widgets manually. All functionality requires a live Docker daemon.

## Architecture

Everything lives in a single file: `lazy-cli.plugin.zsh`. It has two distinct sections:

**Docker helper functions** (`dlazy-*` prefix):
- `dlazy-find` — thin wrapper around `docker ps --filter`
- `dlazy-find-in-cluster` — iterates contexts sharing a namespace prefix (e.g. `prod.1`, `prod.2`) and calls `dlazy-find` on each; switches the active context to the one where the container was found
- `dlazy-exec` — calls `dlazy-find-in-cluster` then `docker exec -it … bash` (falls back to `sh`)
- `dlazy-foreach-svc` — runs an arbitrary `docker service` action against all services matching a name filter

**fzf ZLE widgets** (`_fzf-*` naming, registered with `zle -N`):
- Each widget populates `LBUFFER` with a command and calls `zle redisplay`, so the user can review and edit before running
- Exception: `_fzf-docker-context` sets `DOCKER_CONTEXT` as a session-local env var (does not run `docker context use` globally) and calls `zle reset-prompt`
- `docker-context-unset` reverses this by unsetting `DOCKER_CONTEXT`

**Namespace convention**: context names are expected to follow `<namespace>.<index>` (e.g. `dev-cluster.1`). `dlazy-find-in-cluster` strips the suffix with `${current_context%\.*}` to derive the namespace, then greps `docker context ls` for all matching contexts.

## Key constraints

- The plugin file must be named `lazy-cli.plugin.zsh` — this is the entry point expected by Zinit and Oh-My-Zsh (the Oh-My-Zsh plugin directory is named `lazy-cli`).
- `ctrl+l` intentionally overrides Zsh's default clear-screen binding; this is documented in README and in the inline comment.
- fzf widgets use `2>/dev/null` on Docker/git calls so the widget degrades silently when outside a repo or when Docker is unavailable.
