# Claude Code iTerm2 tab-session auto-resume
# 映射文件：iTerm2 tab UUID → claude session ID (TSV: tab_uuid \t session_id \t cwd)
_claude_tab_map="$HOME/.claude/tab-sessions.tsv"

_claude_tab_save() {
  local key="$1" sid="$2" dir="${3:-$PWD}"
  _claude_tab_remove "$key" "$dir"
  printf '%s\t%s\t%s\n' "$key" "$sid" "$dir" >> "$_claude_tab_map"
}

_claude_tab_remove() {
  local key="$1" dir="$2"
  [[ -f "$_claude_tab_map" ]] || return
  local tmp=$(awk -F'\t' -v k="$key" -v d="$dir" '!($1 == k && $3 == d)' "$_claude_tab_map")
  if [[ -n "$tmp" ]]; then
    printf '%s\n' "$tmp" > "$_claude_tab_map"
  else
    : > "$_claude_tab_map"
  fi
}

_claude_tab_lookup() {
  local key="$1" dir="${2:-$PWD}"
  [[ -f "$_claude_tab_map" ]] || return
  awk -F'\t' -v k="$key" -v d="$dir" '$1 == k && $3 == d {print $2; exit}' "$_claude_tab_map"
}

_claude_tab_session_exists() {
  local sid="$1"
  # Check session file only in the project directory matching current PWD
  # (Claude Code maps PWD → project dir by replacing / with -)
  local project_key="$(printf '%s' "$PWD" | tr '/' '-')"
  [[ -f "$HOME/.claude/projects/${project_key}/${sid}.jsonl" ]]
}

_claude_tab_update_from_capture() {
  local key="$1" capture_file="$2"
  [[ -z "$key" || ! -f "$capture_file" ]] && { rm -f "$capture_file"; return; }
  local actual_sid=$(tail -20 "$capture_file" | sed 's/\x1b\[[0-9;]*[a-zA-Z]//g' | grep -oE 'claude --resume [0-9a-f-]{36}' | tail -1 | awk '{print $3}')
  rm -f "$capture_file"
  [[ -z "$actual_sid" ]] && return
  local old_sid=$(_claude_tab_lookup "$key")
  if [[ "$actual_sid" != "$old_sid" ]]; then
    _claude_tab_save "$key" "$actual_sid"
  fi
}

_claude_exec() {
  local tab_key="$1"; shift
  local _capture=$(mktemp)
  script -q "$_capture" /bin/zsh -c 'command claude "$@"' zsh "$@"
  local rc=$?
  _claude_tab_update_from_capture "$tab_key" "$_capture"
  return $rc
}

_claude_gen_uuid() {
  if command -v uuidgen &>/dev/null; then
    uuidgen | tr 'A-Z' 'a-z'
  elif [[ -r /proc/sys/kernel/random/uuid ]]; then
    cat /proc/sys/kernel/random/uuid
  else
    od -x /dev/urandom | head -1 | awk '{print $2$3"-"$4"-"$5"-"$6"-"$7$8$9}'
  fi
}

_claude_socks2http_pid=""

_claude_detect_proxy() {
  # 如果桥接进程还活着，跳过重复启动
  if [[ -n "$_claude_socks2http_pid" ]] && kill -0 "$_claude_socks2http_pid" 2>/dev/null; then
    return
  fi

  # 如果端口已被占用（上一个 shell 留下的桥接），直接复用
  if lsof -iTCP:53731 -sTCP:LISTEN -t &>/dev/null; then
    local proxy_val="http://127.0.0.1:53731"
    export https_proxy="$proxy_val" http_proxy="$proxy_val" all_proxy="$proxy_val"
    export no_proxy="localhost,127.0.0.1,idealab.alibaba-inc.com"
    return
  fi

  command -v node &>/dev/null || return

  local pac_url=$(scutil --proxy 2>/dev/null | awk -F': ' '/ProxyAutoConfigURLString/{print $2}')
  [[ -z "$pac_url" ]] && return
  local socks_port=$(curl -s --max-time 3 "$pac_url" 2>/dev/null | grep -oE 'SOCKS5? 127\.0\.0\.1:[0-9]+' | head -1 | grep -oE '[0-9]+$')
  [[ -z "$socks_port" ]] && return

  local bridge_script="$HOME/.local/bin/socks2http.js"
  [[ -f "$bridge_script" ]] || return

  local node_dir=$(dirname "$(dirname "$(command -v node)")")
  local socks_module=$(find "$node_dir/lib/node_modules" -path "*/socks" -type d -maxdepth 5 2>/dev/null | head -1)
  [[ -z "$socks_module" ]] && return

  local bridge_out=$(mktemp)
  SOCKS_HOST="127.0.0.1" SOCKS_PORT="$socks_port" SOCKS_MODULE="$socks_module" node "$bridge_script" > "$bridge_out" 2>/dev/null &
  _claude_socks2http_pid=$!
  sleep 1

  local bridge_port=$(grep -o '"port":[0-9]*' "$bridge_out" 2>/dev/null | grep -o '[0-9]*')
  rm -f "$bridge_out"

  if [[ -n "$bridge_port" ]] && (( bridge_port > 0 && bridge_port <= 65535 )); then
    local proxy_val="http://127.0.0.1:$bridge_port"
    export https_proxy="$proxy_val"
    export http_proxy="$proxy_val"
    export all_proxy="$proxy_val"
    export no_proxy="localhost,127.0.0.1,idealab.alibaba-inc.com"

    # 写入 settings.json env，让 Claude Code 内部（WebFetch 等）也走代理
    local settings="$HOME/.claude/settings.json"
    if [[ -f "$settings" ]]; then
      sed -i '' \
        -e '/"https_proxy"/d' \
        -e '/"http_proxy"/d' \
        -e '/"all_proxy"/d' \
        -e '/"no_proxy"/d' \
        "$settings"
      sed -i '' "s|\"env\": {|\"env\": {\n    \"https_proxy\": \"$proxy_val\",\n    \"http_proxy\": \"$proxy_val\",\n    \"all_proxy\": \"$proxy_val\",\n    \"no_proxy\": \"localhost,127.0.0.1,idealab.alibaba-inc.com\",|" "$settings"
    fi
  else
    kill "$_claude_socks2http_pid" 2>/dev/null
    _claude_socks2http_pid=""
  fi
}

claude() {
  # If nvm lazy loading is configured, ensure node is available for claude
  if [[ "$_nvm_loaded" == "false" ]] && type lazy_load_nvm &>/dev/null; then
    lazy_load_nvm
  fi

  # 从系统 PAC 自动检测代理，启动 SOCKS5→HTTP 桥接
  _claude_detect_proxy

  local iterm_uuid="${ITERM_SESSION_ID#*:}"

  # tmux 环境下追加 pane ID 以区分不同 pane
  if [[ -n "$TMUX_PANE" ]]; then
    iterm_uuid="${iterm_uuid}_${TMUX_PANE}"
  fi

  # 非 iTerm2 环境 → 直接透传
  if [[ -z "$iterm_uuid" ]]; then
    command claude "$@"
    return
  fi

  # 解析参数：检测会话控制标志和 --new
  local pass_through=false
  local force_new=false
  local clean_args=()

  for arg in "$@"; do
    case "$arg" in
      --resume|-r|--continue|-c|--fork-session|-p|--print|--no-session-persistence|--session-id|--resume=*|-r=*)
        pass_through=true
        clean_args+=("$arg")
        ;;
      --new)
        force_new=true
        ;;
      *)
        clean_args+=("$arg")
        ;;
    esac
  done

  # 用户显式指定会话控制 → 透传，不干预
  if $pass_through; then
    _claude_exec "$iterm_uuid" "${clean_args[@]}"
    return
  fi

  # --new → 强制新建 session，更新映射
  if $force_new; then
    local new_id=$(_claude_gen_uuid)
    _claude_tab_save "$iterm_uuid" "$new_id"
    _claude_exec "$iterm_uuid" --session-id "$new_id" "${clean_args[@]}"
    return
  fi

  # 自动恢复：有映射（uuid+PWD 匹配）→ resume
  local sid=$(_claude_tab_lookup "$iterm_uuid")
  if [[ -n "$sid" ]]; then
    _claude_exec "$iterm_uuid" --resume "$sid" "${clean_args[@]}"
    return
  fi

  # No mapping exists (truly new directory) → new session
  local new_id=$(_claude_gen_uuid)
  _claude_tab_save "$iterm_uuid" "$new_id"
  _claude_exec "$iterm_uuid" --session-id "$new_id" "${clean_args[@]}"
}

# 调试工具：查看当前 tab-session 映射
claude-sessions() {
  if [[ -f "$_claude_tab_map" ]] && [[ -s "$_claude_tab_map" ]]; then
    echo "Tab-Session Mappings:"
    while IFS=$'\t' read -r key sid cwd; do
      [[ -z "$key" ]] && continue
      echo "  ${key:0:8}... → ${sid:0:12}... ($cwd)"
    done < "$_claude_tab_map"
    echo ""
    echo "Current tab: ${ITERM_SESSION_ID#*:}"
  else
    echo "No tab-session mappings found."
  fi
}
