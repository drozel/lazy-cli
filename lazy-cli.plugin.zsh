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
  if [[ -n "$branch" ]]; then
    BUFFER="git checkout $branch"
    zle accept-line
  else
    zle redisplay
  fi
}
zle -N _fzf-git-branch
bindkey '^b' _fzf-git-branch

# Shared container action: builds LBUFFER from (key, container [, context])
_LAZY_CONTAINER_HEADER='[enter] exec  [ctrl-l] logs  [ctrl-v] inspect  [ctrl-s] top'
_LAZY_CONTAINER_EXPECT='ctrl-l,ctrl-v,ctrl-s'
_lazy-container-action() {
  local key="$1" container="$2" ctx="$3"
  local prefix="docker"
  [[ -n "$ctx" ]] && prefix="docker --context $ctx"
  case "$key" in
    ctrl-l) LBUFFER="$prefix logs -f $container" ;;
    ctrl-v) LBUFFER="$prefix inspect $container | jq" ;;
    ctrl-s) LBUFFER="$prefix top $container" ;;
    *)      LBUFFER="$prefix exec -it $container bash" ;;
  esac
}

# ctrl+p: container picker — [enter] exec, [ctrl-l] logs, [ctrl-v] inspect, [ctrl-s] top
_fzf-docker-container() {
  local fzf_out key container_line container

  fzf_out=$(docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}' 2>/dev/null \
    | tail -n +2 \
    | fzf --height 40% --reverse --prompt="container> " \
      --header="$_LAZY_CONTAINER_HEADER" \
      --expect="$_LAZY_CONTAINER_EXPECT")

  [[ -z "$fzf_out" ]] && zle redisplay && return

  key=$(printf '%s' "$fzf_out" | head -1)
  container_line=$(printf '%s' "$fzf_out" | sed -n '2p')
  [[ -z "$container_line" ]] && zle redisplay && return

  container=$(printf '%s' "$container_line" | awk '{print $1}')
  [[ -z "$container" ]] && zle redisplay && return

  _lazy-container-action "$key" "$container"
  zle redisplay
}
zle -N _fzf-docker-container
bindkey '^p' _fzf-docker-container

# ctrl+o: swarm service picker — [enter] containers, [ctrl-l] logs, [ctrl-s] ps, [ctrl-v] inspect
_fzf-docker-service-exec() {
  local fzf_svc key_svc service_line service
  fzf_svc=$(docker service ls --format '{{.Name}}\t{{.Mode}}\t{{.Replicas}}' 2>/dev/null \
    | column -t \
    | fzf --height 40% --reverse --prompt="service> " \
      --header='[enter] containers  [ctrl-l] logs  [ctrl-s] ps  [ctrl-v] inspect' \
      --expect=ctrl-l,ctrl-s,ctrl-v)
  [[ -z "$fzf_svc" ]] && zle redisplay && return

  key_svc=$(printf '%s' "$fzf_svc" | head -1)
  service_line=$(printf '%s' "$fzf_svc" | sed -n '2p')
  [[ -z "$service_line" ]] && zle redisplay && return

  service=$(printf '%s' "$service_line" | awk '{print $1}')
  [[ -z "$service" ]] && zle redisplay && return

  case "$key_svc" in
    ctrl-l) LBUFFER="docker service logs -f $service"; zle redisplay; return ;;
    ctrl-s) LBUFFER="docker service ps $service";      zle redisplay; return ;;
    ctrl-v) LBUFFER="docker service inspect $service"; zle redisplay; return ;;
  esac

  local current_context base_name
  current_context=$(docker context show 2>/dev/null)
  base_name="${current_context%.*}"

  local entries=()
  while IFS= read -r ctx; do
    while IFS= read -r name; do
      [[ -n "$name" ]] && entries+=("${ctx}	${name}")
    done < <(docker --context "$ctx" ps --filter "name=$service" \
      --format '{{.Names}}' 2>/dev/null | grep "^${service}\.")
  done < <(docker context ls --format '{{.Name}}' 2>/dev/null | grep "^${base_name}")

  [[ ${#entries[@]} -eq 0 ]] && zle redisplay && return

  local selection
  selection=$(printf '%s\n' "${entries[@]}" \
    | fzf --height 40% --reverse --prompt="container> " \
      --delimiter=$'\t' --with-nth='1,2' \
      --disabled \
      --header="$_LAZY_CONTAINER_HEADER" \
      --expect="$_LAZY_CONTAINER_EXPECT")
  [[ -z "$selection" ]] && zle redisplay && return

  local key container_line
  key=$(printf '%s' "$selection" | head -1)
  container_line=$(printf '%s' "$selection" | sed -n '2p')
  [[ -z "$container_line" ]] && zle redisplay && return

  local ctx container
  ctx=$(printf '%s' "$container_line" | cut -f1)
  container=$(printf '%s' "$container_line" | cut -f2)

  _lazy-container-action "$key" "$container" "$ctx"
  zle redisplay
}
zle -N _fzf-docker-service-exec
bindkey '^o' _fzf-docker-service-exec

# ctrl+t: pick a Taskfile task — [enter] run, [alt-enter] paste only
_fzf-task() {
  local fzf_out key task_line task
  fzf_out=$(task --list-all 2>/dev/null \
    | grep '^\*' \
    | fzf --height 40% --reverse --prompt="task> " \
      --header='[enter] run  [alt-enter] paste only' \
      --expect=alt-enter)

  [[ -z "$fzf_out" ]] && zle redisplay && return

  key=$(printf '%s' "$fzf_out" | head -1)
  task_line=$(printf '%s' "$fzf_out" | sed -n '2p')
  [[ -z "$task_line" ]] && zle redisplay && return

  task=$(printf '%s' "$task_line" | awk '{print $2}' | sed 's/:$//')
  [[ -z "$task" ]] && zle redisplay && return

  if [[ "$key" == "alt-enter" ]]; then
    LBUFFER="task $task"
    zle redisplay
  else
    BUFFER="task $task"
    zle accept-line
  fi
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
  ctrl+p   docker container     (exec / logs / inspect / top)
  ctrl+o   docker swarm         (list of services and quick actions)
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
