#!/usr/bin/env bash
set -euo pipefail

# ─── 配置 ───────────────────────────────────────────────
SKILLS_DIR="$HOME/.claude/skills"
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"

# ─── 颜色 ───────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# ─── 辅助函数 ───────────────────────────────────────────
info()    { echo -e "${CYAN}ℹ${NC}  $*"; }
success() { echo -e "${GREEN}✔${NC}  $*"; }
warn()    { echo -e "${YELLOW}⚠${NC}  $*"; }
error()   { echo -e "${RED}✘${NC}  $*" >&2; }

# 自动发现 repo 中所有包含 SKILL.md 的目录
discover_skills() {
  local skills=()
  for dir in "$REPO_DIR"/*/; do
    [ -f "$dir/SKILL.md" ] && skills+=("$(basename "$dir")")
  done
  echo "${skills[@]}"
}

# 链接单个 skill
link_skill() {
  local skill="$1"
  local src="$REPO_DIR/$skill"
  local dst="$SKILLS_DIR/$skill"

  if [ ! -d "$src" ]; then
    error "技能 ${BOLD}$skill${NC} 不存在于 $REPO_DIR"
    return 1
  fi
  if [ ! -f "$src/SKILL.md" ]; then
    error "目录 ${BOLD}$skill${NC} 不包含 SKILL.md，不是有效技能"
    return 1
  fi

  # 如果目标已存在
  if [ -L "$dst" ]; then
    local current_target
    current_target="$(readlink "$dst")"
    if [ "$current_target" = "$src" ]; then
      warn "${BOLD}$skill${NC} 已链接（跳过）"
      return 0
    fi
    warn "${BOLD}$skill${NC} 已链接到其他位置 → 更新"
    rm "$dst"
  elif [ -e "$dst" ]; then
    error "${BOLD}$dst${NC} 已存在且不是符号链接，请手动处理"
    return 1
  fi

  ln -s "$src" "$dst"
  success "${BOLD}$skill${NC}  →  $dst"
}

# 移除单个 skill 的链接
unlink_skill() {
  local skill="$1"
  local dst="$SKILLS_DIR/$skill"

  if [ -L "$dst" ]; then
    rm "$dst"
    success "已移除 ${BOLD}$skill${NC}"
  elif [ -e "$dst" ]; then
    warn "${BOLD}$dst${NC} 不是符号链接，跳过"
  else
    warn "${BOLD}$skill${NC} 未安装"
  fi
}

# ─── 命令处理 ───────────────────────────────────────────
cmd_install() {
  local skills=("$@")

  # 无参数 → 安装全部
  if [ ${#skills[@]} -eq 0 ]; then
    read -ra skills <<< "$(discover_skills)"
    if [ ${#skills[@]} -eq 0 ]; then
      error "未发现任何技能（缺少 SKILL.md）"
      exit 1
    fi
    info "安装全部技能: ${BOLD}${skills[*]}${NC}"
  fi

  # 确保目标目录存在
  mkdir -p "$SKILLS_DIR"

  for skill in "${skills[@]}"; do
    link_skill "$skill"
  done

  echo ""
  success "完成！Claude Code 现在可以使用已安装的技能。"
}

cmd_uninstall() {
  local skills=("$@")

  if [ ${#skills[@]} -eq 0 ]; then
    read -ra skills <<< "$(discover_skills)"
    info "移除全部技能: ${BOLD}${skills[*]}${NC}"
  fi

  for skill in "${skills[@]}"; do
    unlink_skill "$skill"
  done

  success "完成！"
}

cmd_list() {
  local skills
  read -ra skills <<< "$(discover_skills)"

  if [ ${#skills[@]} -eq 0 ]; then
    warn "未发现任何技能"
    return
  fi

  echo -e "${BOLD}可用技能：${NC}"
  echo ""
  for skill in "${skills[@]}"; do
    local dst="$SKILLS_DIR/$skill"
    if [ -L "$dst" ]; then
      echo -e "  ${GREEN}●${NC} ${BOLD}$skill${NC}  (已安装)"
    else
      echo -e "  ${RED}○${NC} $skill"
    fi
  done
  echo ""
}

cmd_status() {
  echo -e "${BOLD}仓库路径：${NC} $REPO_DIR"
  echo -e "${BOLD}技能目录：${NC} $SKILLS_DIR"
  echo ""
  cmd_list
}

# ─── 帮助信息 ───────────────────────────────────────────
usage() {
  cat <<EOF
${BOLD}Claude Skills Installer${NC}

用法：
  $(basename "$0") [命令] [技能名称...]

命令：
  install [skill...]   安装技能（无参数则安装全部）
  uninstall [skill...] 移除技能（无参数则移除全部）
  list                 列出可用技能及安装状态
  status               显示配置信息及技能状态
  help                 显示此帮助信息

示例：
  $(basename "$0") install              # 安装全部技能
  $(basename "$0") install paper-fetcher # 只安装 paper-fetcher
  $(basename "$0") uninstall            # 移除全部技能
  $(basename "$0") list                 # 查看可用技能

原理：
  在 ~/.claude/skills/ 中创建符号链接指向本仓库中的技能目录，
  Claude Code 会自动识别并加载这些技能。
EOF
}

# ─── 主入口 ─────────────────────────────────────────────
main() {
  local cmd="${1:-install}"
  shift 2>/dev/null || true

  case "$cmd" in
    install)    cmd_install "$@" ;;
    uninstall)  cmd_uninstall "$@" ;;
    list)       cmd_list ;;
    status)     cmd_status ;;
    help|-h|--help) usage ;;
    *)
      error "未知命令: $cmd"
      echo ""
      usage
      exit 1
      ;;
  esac
}

main "$@"
