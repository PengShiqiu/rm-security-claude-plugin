#!/bin/bash
# script-content-checker.sh - 监控写入的脚本内容是否包含危险命令
# 位置: ~/.claude/hooks/scripts/script-content-checker.sh
# 功能：检测 Write/Edit 工具创建的脚本文件是否包含删除命令

set -e

LOG_FILE="/tmp/rm-interceptor.log"
PENDING_DELETIONS_FILE="/tmp/rm-pending-deletions.txt"

log_debug() {
    if [ "${RM_INTERCEPTOR_DEBUG:-0}" = "1" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [content-checker] $1" >> "$LOG_FILE"
    fi
}

# 从 stdin 读取 JSON 输入
INPUT=$(cat)
log_debug "收到输入"

# 提取工具输入内容
extract_tool_input() {
    local input="$1"

    if command -v python3 &>/dev/null; then
        echo "$input" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    tool_input = data.get('tool_input', {})
    print(json.dumps(tool_input))
except:
    pass
" 2>/dev/null
    fi
}

TOOL_INPUT=$(extract_tool_input "$INPUT")

if [ -z "$TOOL_INPUT" ]; then
    log_debug "无法提取工具输入"
    exit 0
fi

# 提取文件路径和内容
extract_file_path() {
    echo "$TOOL_INPUT" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data.get('file_path', ''))
except:
    pass
" 2>/dev/null
}

extract_content() {
    echo "$TOOL_INPUT" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    # Write 工具
    if 'content' in data:
        print(data['content'])
    # Edit 工具
    elif 'new_string' in data:
        print(data['new_string'])
except:
    pass
" 2>/dev/null
}

FILE_PATH=$(extract_file_path)
CONTENT=$(extract_content)

log_debug "文件路径: $FILE_PATH"
log_debug "内容长度: ${#CONTENT}"

if [ -z "$CONTENT" ]; then
    exit 0
fi

# 检查是否是脚本文件
is_script_file() {
    local path="$1"
    local content="$2"

    # 通过扩展名判断
    case "$path" in
        *.sh|*.bash|*.zsh|*.ksh|*.fish)
            return 0
            ;;
        *.py)
            return 0
            ;;
        *.pl|*.pm)
            return 0
            ;;
        *.rb)
            return 0
            ;;
        *.js|*.mjs)
            return 0
            ;;
    esac

    # 通过 shebang 判断
    if echo "$content" | head -1 | grep -qE '^#!.*(bash|sh|python|perl|ruby|node|js)'; then
        return 0
    fi

    return 1
}

# 检查内容是否包含危险命令
check_dangerous_content() {
    local content="$1"
    local file_path="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # 检测 rm 命令
    if echo "$content" | grep -qE '(^|[[:space:];&|])rm([[:space:]]|$)'; then
        # 提取 rm 命令行
        local rm_lines=$(echo "$content" | grep -n 'rm' | head -5)

        cat >&2 << EOF

╔══════════════════════════════════════════════════════════════════════╗
║                 ⚠️  检测到脚本包含删除命令                           ║
╠══════════════════════════════════════════════════════════════════════╣
║                                                                      ║
║  文件: $FILE_PATH
║                                                                      ║
║  发现以下包含 rm 命令的行:                                           ║
$(echo "$rm_lines" | sed 's/^/║  /')
║                                                                      ║
╠══════════════════════════════════════════════════════════════════════╣
║                                                                      ║
║  📋 此脚本已被标记，执行时会被拦截                                   ║
║                                                                      ║
║  如果您需要创建删除脚本，建议:                                       ║
║    1. 创建脚本时不要包含实际路径                                     ║
║    2. 让用户手动填充路径并执行                                       ║
║                                                                      ║
╚══════════════════════════════════════════════════════════════════════╝

EOF

        # 记录到待删除列表
        {
            echo "[$timestamp] 脚本包含删除命令"
            echo "  文件: $file_path"
            echo "  内容预览:"
            echo "$rm_lines" | sed 's/^/    /'
            echo ""
        } >> "$PENDING_DELETIONS_FILE"

        return 0
    fi

    # 检测 Python 删除操作
    if echo "$content" | grep -qE 'os\.(remove|unlink|rmdir)\s*\(' | grep -v '#'; then
        cat >&2 << EOF

╔══════════════════════════════════════════════════════════════════════╗
║                 ⚠️  检测到 Python 脚本包含删除操作                   ║
╠══════════════════════════════════════════════════════════════════════╣
║                                                                      ║
║  文件: $FILE_PATH
║                                                                      ║
║  发现 os.remove / os.unlink / os.rmdir 调用                         ║
║                                                                      ║
╚══════════════════════════════════════════════════════════════════════╝

EOF

        {
            echo "[$timestamp] Python 脚本包含删除操作"
            echo "  文件: $file_path"
            echo ""
        } >> "$PENDING_DELETIONS_FILE"

        return 0
    fi

    # 检测 shutil.rmtree
    if echo "$content" | grep -qE 'shutil\.rmtree\s*\(' | grep -v '#'; then
        cat >&2 << EOF

╔══════════════════════════════════════════════════════════════════════╗
║                 ⚠️  检测到 Python 脚本包含目录删除操作               ║
╠══════════════════════════════════════════════════════════════════════╣
║                                                                      ║
║  文件: $FILE_PATH
║                                                                      ║
║  发现 shutil.rmtree 调用 - 会删除整个目录                            ║
║                                                                      ║
╚══════════════════════════════════════════════════════════════════════╝

EOF

        {
            echo "[$timestamp] Python 脚本包含 shutil.rmtree"
            echo "  文件: $file_path"
            echo ""
        } >> "$PENDING_DELETIONS_FILE"

        return 0
    fi

    return 1
}

# 只检查脚本文件
if is_script_file "$FILE_PATH" "$CONTENT"; then
    log_debug "检测到脚本文件: $FILE_PATH"

    # 检查内容是否包含危险命令（但不阻止写入，只警告）
    check_dangerous_content "$CONTENT" "$FILE_PATH" || true
fi

# 允许写入
exit 0
