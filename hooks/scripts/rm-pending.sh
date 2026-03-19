#!/bin/bash
# rm-pending.sh - 管理待删除文件列表
# 用法:
#   rm-pending.sh list    - 查看待删除列表
#   rm-pending.sh clear   - 清空待删除列表
#   rm-pending.sh exec    - 执行待删除列表中的删除操作（需确认）
#   rm-pending.sh json    - 以 JSON 格式输出

PENDING_FILE="/tmp/rm-pending-deletions.txt"
PENDING_JSON="/tmp/rm-pending-deletions.json"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

show_help() {
    cat << 'EOF'
rm-pending.sh - 管理待删除文件列表

用法:
    rm-pending.sh list      查看待删除列表
    rm-pending.sh clear     清空待删除列表
    rm-pending.sh exec      执行待删除操作（交互式确认）
    rm-pending.sh json      以 JSON 格式输出列表
    rm-pending.sh help      显示此帮助信息

说明:
    当 Claude Code Agent 尝试执行删除操作时，会被拦截并记录到此列表。
    用户可以查看列表内容，确认后手动执行删除。

示例:
    # 查看待删除列表
    rm-pending.sh list

    # 清空列表（不执行删除）
    rm-pending.sh clear

    # 执行删除（会逐个确认）
    rm-pending.sh exec
EOF
}

list_pending() {
    if [ ! -f "$PENDING_FILE" ] || [ ! -s "$PENDING_FILE" ]; then
        echo -e "${GREEN}✓ 待删除列表为空${NC}"
        return 0
    fi

    echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}                    待删除文件列表${NC}"
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
    echo ""

    cat "$PENDING_FILE"

    echo ""
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"

    # 统计数量
    local count=$(grep -c "^\[" "$PENDING_FILE" 2>/dev/null || echo "0")
    echo -e "共 ${RED}$count${NC} 个待删除项"
    echo ""
    echo "执行删除: rm-pending.sh exec"
    echo "清空列表: rm-pending.sh clear"
}

list_json() {
    if [ -f "$PENDING_JSON" ]; then
        cat "$PENDING_JSON"
    else
        echo "[]"
    fi
}

clear_pending() {
    rm -f "$PENDING_FILE" "$PENDING_JSON" 2>/dev/null
    echo -e "${GREEN}✓ 待删除列表已清空${NC}"
}

exec_pending() {
    if [ ! -f "$PENDING_FILE" ] || [ ! -s "$PENDING_FILE" ]; then
        echo -e "${GREEN}✓ 待删除列表为空，无需执行${NC}"
        return 0
    fi

    echo -e "${RED}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${RED}              ⚠️  警告：即将执行删除操作${NC}"
    echo -e "${RED}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    cat "$PENDING_FILE"
    echo ""

    echo -e "${RED}请仔细检查以上内容，确认是否要执行删除？${NC}"
    echo -n "输入 'yes' 确认执行: "
    read -r confirm

    if [ "$confirm" != "yes" ]; then
        echo -e "${YELLOW}已取消${NC}"
        return 1
    fi

    # 从 JSON 文件提取路径并执行删除
    if [ -f "$PENDING_JSON" ] && command -v python3 &>/dev/null; then
        echo ""
        echo "开始执行删除..."

        python3 << 'PYEOF'
import json
import subprocess
import sys
import os

with open('/tmp/rm-pending-deletions.json', 'r') as f:
    entries = json.load(f)

all_paths = set()
for entry in entries:
    for path in entry.get('paths', []):
        if path and os.path.exists(path):
            all_paths.add(path)

if not all_paths:
    print("没有找到需要删除的文件")
    sys.exit(0)

print(f"将删除 {len(all_paths)} 个文件/目录:")
for p in sorted(all_paths):
    print(f"  - {p}")

print()
confirm = input("最终确认，输入 'DELETE' 继续: ")
if confirm == 'DELETE':
    for path in sorted(all_paths):
        try:
            if os.path.isdir(path):
                subprocess.run(['rm', '-rf', path], check=True)
                print(f"✓ 已删除目录: {path}")
            else:
                subprocess.run(['rm', '-f', path], check=True)
                print(f"✓ 已删除文件: {path}")
        except Exception as e:
            print(f"✗ 删除失败: {path} - {e}")
    print("删除完成")
else:
    print("已取消")
PYEOF

    else
        echo -e "${YELLOW}无法自动执行，请手动处理${NC}"
        echo "查看命令: cat $PENDING_FILE"
    fi
}

case "${1:-list}" in
    list|ls)
        list_pending
        ;;
    json)
        list_json
        ;;
    clear|clean)
        clear_pending
        ;;
    exec|run)
        exec_pending
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        echo "未知命令: $1"
        show_help
        exit 1
        ;;
esac
