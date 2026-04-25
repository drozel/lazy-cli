function dlazy-help() {
    echo "dlazy - Docker lazy commands"
    echo "Docker-lazy is a set of helper functions for Docker CLI, especially useful for managing Swarm clusters."
    echo ""
    echo "Docker-lazy assumes you are using Docker contexts, grouped into namespaces to manage multiple environments. Different nodes of one cluster would be contexts in the same namespace."
    echo "For example, if you have a context named 'dev-cluster.1' and another named 'dev-cluster.2', they belong to the same namespace 'dev-cluster' and Docker-lazy will be able to find containers across them (e.g. using dlazy-find-in-cluster)."
    echo ""
    echo "Commands:"
    echo "  dlazy-help                             Prints this help."
    echo "  dlazy-find <container_name>            Returns the ID of a container matching to given name (partial search). Uses only current context."
    echo "  dlazy-find-in-cluster <container_name> Find the contexts running a container with desired name starting with the current one. Contexts are expected to be grouped into namespaces."
    echo "  dexecp <container_name>       Exec bash (or sh as fallback) in a Docker container by name across all contexts from the same namespace."
    echo "  dlogs <container_name>        Show logs for a Docker container by name in the current context."
    echo "  dforservice <filter> <action> Execute an action on all services matching the filter."
}
function dlazy-find() {
    if [[ $1 == "--help" ]]; then
        echo "Usage: $0 <container_name>"
        echo "Find a Docker container(s) by name in the current context. Returns the container ID(s). Name can be partial."
        return 0
    fi

    containers=$(docker ps --filter "name=$1" --format "{{.ID}}")
    echo $containers
}

function dlazy-find-in-cluster() {
    if [[ $1 == "--help" ]]; then
        echo "Usage: $0 <container_name>"
        echo "Find a Docker container by name across all contexts from the same namespace and switch to it."
        return 0
    fi

    container_name=$1
    current_context=$(docker context show)
    base_name="${current_context%\.*}"
    local available_contexts=("${(@f)$(docker context ls --format "{{.Name}}" | grep "^$base_name")}")

    # Ensure the current context is the first in the list
    available_contexts=("$current_context" "${(@)available_contexts:#$current_context}")

    for target_context in "${available_contexts[@]}"; do
        echo "Checking context: $target_context"

        docker context use "$target_context" >/dev/null 2>&1
        if [ $? -ne 0 ]; then
            echo "Failed to switch to context $target_context, skipping."
            continue
        fi

        # Check for the container by name in the target context
        container_id=$(dlazy-find $container_name)
        if [ -n "$container_id" ]; then
            echo "Container '$container_name' found in context $target_context"
            echo "Switched to context $target_context"
            return 0
        fi
    done
    echo "Container '$container_name' not found in any context."
    docker context use "$current_context" >/dev/null 2>&1
    return 1
}

function dlazy-exec() {
    if [[ $1 == "--help" ]]; then
        echo "Usage: $0 <container_name>"
        echo "Exec bash (or sh as fallback) in a Docker container by name across all contexts from the same namespace. Enters the first found if multiple."
        return 0
    fi
    dlazy-find-in-cluster $1
    if [ $? -ne 0 ]; then
        echo "Container '$1' not found in any context."
        return 1
    fi

    container_ids=$(dlazy-find $1)
    if [[ $(echo "$container_ids" | wc -l) -ne 1 ]]; then
        container_ids=$(echo "$container_ids" | head -n 1)
        container_name=$(docker ps --filter "id=$container_ids" --format "{{.Names}}")
        echo "Found more than one container on the node, using the first: $container_name"
    fi

    docker exec -it $container_ids bash || docker exec -it $container_ids sh 
}

function dlazy-foreach-svc() {
    if [[ $1 == "--help" ]]; then
        echo "Usage: $0 <service_name> <action>"
        echo "Execute an action on all services matching the filter. E.g.: `$0 database rm` will invoke `docker service rm <service>` multiple times for each service having <service_name> in its name."
        return 0
    fi
    local filter="$1"
    shift
    local action="$1"
    shift
    for n in $(docker service ls --filter name="$filter" -q); do
        eval "$action $@" "$n"
    done
}

# ---------------------------------------------------------------------------
# fzf widgets — require fzf in PATH
# ---------------------------------------------------------------------------

# ctrl+x: switch docker context (local to terminal); colima first, no default
_fzf-docker-context() {
  local ctx
  ctx=$(docker context ls --format '{{.Name}}' 2>/dev/null \
    | grep -v '^default$' \
    | awk '/^colima$/{print; next} {rest[++n]=$0} END{for(i=1;i<=n;i++) print rest[i]}' \
    | fzf --height 40% --reverse --prompt="docker context> ")
  [[ -n "$ctx" ]] && export DOCKER_CONTEXT="$ctx" && echo "Docker context: $ctx"
  zle reset-prompt
}
zle -N _fzf-docker-context
bindkey '^x' _fzf-docker-context

# ctrl+b: git branch picker sorted by most recent commit
_fzf-git-branch() {
  local branch
  branch=$(git for-each-ref --sort=-committerdate refs/heads/ \
    --format='%(color:yellow)%(committerdate:relative)|%(color:reset)%(refname:short)' \
    2>/dev/null \
    | column -t -s '|' \
    | fzf --height 40% --reverse --prompt="branch> " --ansi \
    | awk '{print $NF}')
  [[ -n "$branch" ]] && LBUFFER="git checkout $branch"
  zle redisplay
}
zle -N _fzf-git-branch
bindkey '^b' _fzf-git-branch

# ctrl+e: exec into a running container
_fzf-docker-exec() {
  local container
  container=$(docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}' 2>/dev/null \
    | tail -n +2 \
    | fzf --height 40% --reverse --prompt="exec> " \
    | awk '{print $1}')
  [[ -n "$container" ]] && LBUFFER="docker exec -it $container bash"
  zle redisplay
}
zle -N _fzf-docker-exec
bindkey '^e' _fzf-docker-exec

# ctrl+l: tail logs of a running container (overrides clear-screen; use 'reset' or 'clear' instead)
_fzf-docker-logs() {
  local container
  container=$(docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}' 2>/dev/null \
    | tail -n +2 \
    | fzf --height 40% --reverse --prompt="logs> " \
    | awk '{print $1}')
  [[ -n "$container" ]] && LBUFFER="docker logs -f $container"
  zle redisplay
}
zle -N _fzf-docker-logs
bindkey '^l' _fzf-docker-logs

# ctrl+shift+l (escape+L): tail logs of a docker swarm service
_fzf-docker-service-logs() {
  local service
  service=$(docker service ls --format 'table {{.Name}}\t{{.Image}}\t{{.Replicas}}' 2>/dev/null \
    | tail -n +2 \
    | fzf --height 40% --reverse --prompt="service logs> " \
    | awk '{print $1}')
  [[ -n "$service" ]] && LBUFFER="docker service logs -f $service"
  zle redisplay
}
zle -N _fzf-docker-service-logs
bindkey '\eL' _fzf-docker-service-logs

# ctrl+t: pick a Taskfile task
_fzf-task() {
  local task
  task=$(task --list-all 2>/dev/null \
    | grep '^\*' \
    | fzf --height 40% --reverse --prompt="task> " \
    | awk '{print $2}' | tr -d ':')
  [[ -n "$task" ]] && LBUFFER="task $task"
  zle redisplay
}
zle -N _fzf-task
bindkey '^t' _fzf-task

# ctrl+g: browse git log with diff preview
_fzf-git-log() {
  local commit
  commit=$(git log --oneline --color=always 2>/dev/null \
    | fzf --height 60% --reverse --prompt="log> " --ansi \
      --preview 'git show --color=always {1}' \
      --preview-window=right:60% \
    | awk '{print $1}')
  [[ -n "$commit" ]] && LBUFFER="git show $commit"
  zle redisplay
}
zle -N _fzf-git-log
bindkey '^g' _fzf-git-log

# ctrl+h: show shortcuts cheatsheet
# Note: ctrl+h sends \x08 (ASCII backspace); physical backspace sends \x7f so this is safe on most terminals
_fzf-help() {
  if [[ -n "$POSTDISPLAY" ]]; then
    POSTDISPLAY=''
  else
    POSTDISPLAY='
Shell shortcuts:
  ctrl+r   history (atuin)
  ctrl+b   git branch picker    (by recency)
  ctrl+g   git log browser      (with diff preview)
  ctrl+x   docker context       (local to terminal)
  ctrl+e   docker exec          (into container)
  ctrl+l   docker logs          (container)
  esc+L    docker service logs  (swarm)
  ctrl+t   task picker
  ctrl+h   toggle this help'
  fi
}
zle -N _fzf-help
bindkey '^h' _fzf-help

# unset local Docker context override (fall back to system-wide context)
docker-context-unset() {
  unset DOCKER_CONTEXT
  echo "Using global Docker context: $(docker context show)"
  zle reset-prompt 2>/dev/null || true
}