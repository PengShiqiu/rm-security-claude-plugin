#!/bin/bash
# rm-pending.sh - 查看待删除文件列表（只读）
# 用法:
#   rm-pending.sh list    - 查看待删除列表
#   rm-pending.sh json    - 以 JSON 格式输出

PENDING_FILE="/tmp/rm-pending-deletions.txt"
PENDING_JSON="/tmp/rm-pending-deletions.json"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

list_pending() {
    if [ ! -f "$PENDING_FILE" ] || [ ! -s "$PENDING_FILE" ]; then
        echo -e "${GREEN}✓ 待删除列表为空${NC}"
        return 0
    fi

    echo -e "${YELLOW}════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}                 待删除文件列表${NC}"
    echo -e "${YELLOW}════════════════════════════════════════════════════${NC}"
    echo ""
    cat "$PENDING_FILE"
    echo ""
    echo -e "${YELLOW}════════════════════════════════════════════════════${NC}"

    local count=$(grep -c "^\[" "$PENDING_FILE" 2>/dev/null || echo "0")
    echo -e "共 ${RED}$count${NC} 个待删除项"
}

list_json() {
    if [ -f "$PENDING_JSON" ]; then
        cat "$PENDING_JSON"
    else
        echo "[]"
    fi
}

case "${1:-list}" in
    list|ls)
        list_pending
        ;;
    json)
        list_json
        ;;
    *)
        echo "用法: rm-pending.sh [list|json]"
        exit 1
        ;;
esac
