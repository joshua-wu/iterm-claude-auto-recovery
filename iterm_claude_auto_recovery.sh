# Claude Code iTerm2 tab-session auto-resume
# 映射文件：iTerm2 tab UUID → claude session ID (TSV: tab_uuid \t session_id \t cwd)
_claude_tab_map="$HOME/.claude/tab-sessions.tsv"

_claude_tab_save() {
  local key="$1" sid="$2"
  _claude_tab_remove "$key"
  printf '%s\t%s\t%s\n' "$key" "$sid" "$PWD" >> "$_claude_tab_map"
}

_claude_tab_remove() {
  local key="$1"
  [[ -f "$_claude_tab_map" ]] || return
  local tmp=$(grep -v "^${key}	" "$_claude_tab_map")
  if [[ -n "$tmp" ]]; then
    printf '%s\n' "$tmp" > "$_claude_tab_map"
  else
    : > "$_claude_tab_map"
  fi
}

_claude_tab_lookup() {
  local key="$1" field="$2"
  [[ -f "$_claude_tab_map" ]] || return
  local line=$(grep "^${key}	" "$_claude_tab_map" | head -1)
  [[ -z "$line" ]] && return
  case "$field" in
    sid) printf '%s' "$line" | cut -f2 ;;
    cwd) printf '%s' "$line" | cut -f3 ;;
  esac
}

_claude_tab_session_exists() {
  local sid="$1"
  [[ -n $(find "$HOME/.claude/projects" -maxdepth 2 -name "${sid}.jsonl" -print -quit 2>/dev/null) ]]
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

claude() {
  # If nvm lazy loading is configured, ensure node is available for claude
  if [[ "$_nvm_loaded" == "false" ]] && type lazy_load_nvm &>/dev/null; then
    lazy_load_nvm
  fi

  local iterm_uuid="${ITERM_SESSION_ID#*:}"

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
    command claude "${clean_args[@]}"
    return
  fi

  # --new → 强制新建 session，更新映射
  if $force_new; then
    local new_id=$(_claude_gen_uuid)
    _claude_tab_save "$iterm_uuid" "$new_id"
    command claude --session-id "$new_id" "${clean_args[@]}"
    return
  fi

  # 自动恢复：查映射 → 验证 session 文件存在 → resume
  local sid=$(_claude_tab_lookup "$iterm_uuid" sid)
  local saved_cwd=$(_claude_tab_lookup "$iterm_uuid" cwd)
  if [[ -n "$sid" ]]; then
    if [[ "$saved_cwd" == "$PWD" ]] && _claude_tab_session_exists "$sid"; then
      command claude --resume "$sid" "${clean_args[@]}"
      return
    else
      _claude_tab_remove "$iterm_uuid"
    fi
  fi

  # 新建 session
  local new_id=$(_claude_gen_uuid)
  _claude_tab_save "$iterm_uuid" "$new_id"
  command claude --session-id "$new_id" "${clean_args[@]}"
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
