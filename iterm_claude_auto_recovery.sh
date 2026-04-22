# Claude Code iTerm2 tab-session auto-resume
# 映射文件：iTerm2 tab UUID → claude session ID
_claude_tab_map="$HOME/.claude/tab-sessions.json"

_claude_tab_save() {
  local key="$1" sid="$2"
  [[ -f "$_claude_tab_map" ]] || echo '{}' > "$_claude_tab_map"
  local tmp=$(jq --arg k "$key" --arg s "$sid" --arg d "$PWD" \
    '.[$k] = {sessionId: $s, cwd: $d}' "$_claude_tab_map" 2>/dev/null)
  [[ -n "$tmp" ]] && echo "$tmp" > "$_claude_tab_map"
}

_claude_tab_remove() {
  local key="$1"
  [[ -f "$_claude_tab_map" ]] || return
  local tmp=$(jq --arg k "$key" 'del(.[$k])' "$_claude_tab_map" 2>/dev/null)
  [[ -n "$tmp" ]] && echo "$tmp" > "$_claude_tab_map"
}

_claude_tab_session_exists() {
  local sid="$1"
  [[ -n $(find "$HOME/.claude/projects" -name "${sid}.jsonl" -maxdepth 2 -print -quit 2>/dev/null) ]]
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
    local new_id=$(uuidgen | tr 'A-Z' 'a-z')
    _claude_tab_save "$iterm_uuid" "$new_id"
    command claude --session-id "$new_id" "${clean_args[@]}"
    return
  fi

  # 自动恢复：查映射 → 验证 session 文件存在 → resume
  if [[ -f "$_claude_tab_map" ]]; then
    local sid=$(jq -r --arg k "$iterm_uuid" '.[$k].sessionId // empty' "$_claude_tab_map" 2>/dev/null)
    local saved_cwd=$(jq -r --arg k "$iterm_uuid" '.[$k].cwd // empty' "$_claude_tab_map" 2>/dev/null)
    if [[ -n "$sid" ]]; then
      if [[ "$saved_cwd" == "$PWD" ]] && _claude_tab_session_exists "$sid"; then
        command claude --resume "$sid" "${clean_args[@]}"
        return
      else
        _claude_tab_remove "$iterm_uuid"
      fi
    fi
  fi

  # 新建 session
  local new_id=$(uuidgen | tr 'A-Z' 'a-z')
  _claude_tab_save "$iterm_uuid" "$new_id"
  command claude --session-id "$new_id" "${clean_args[@]}"
}

# 调试工具：查看当前 tab-session 映射
claude-sessions() {
  if [[ -f "$_claude_tab_map" ]]; then
    echo "Tab-Session Mappings:"
    jq -r 'to_entries[] | "  \(.key[:8])... → \(.value.sessionId[:12])... (\(.value.cwd))"' "$_claude_tab_map"
    echo ""
    echo "Current tab: ${ITERM_SESSION_ID#*:}"
  else
    echo "No tab-session mappings found."
  fi
}
