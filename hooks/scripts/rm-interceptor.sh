#!/bin/bash
# rm-interceptor.sh - 拦截 rm 及各种删除命令的 Hook 脚本
# 参考: test-rm-security.sh 测试套件
# 位置: ~/.claude/hooks/scripts/rm-interceptor.sh
# 功能：拦截删除操作，记录待删除内容，供用户确认

set -e

# 配置
LOG_FILE="/tmp/rm-interceptor.log"
PENDING_DELETIONS_FILE="/tmp/rm-pending-deletions.txt"
PENDING_DELETIONS_JSON="/tmp/rm-pending-deletions.json"

log_debug() {
    if [ "${RM_INTERCEPTOR_DEBUG:-0}" = "1" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
    fi
}

# 从 stdin 读取 JSON 输入
INPUT=$(cat)
log_debug "收到输入: $INPUT"

# 提取 command 字段
extract_command() {
    local input="$1"

    if command -v python3 &>/dev/null; then
        local cmd=$(echo "$input" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    cmd = data.get('tool_input', {}).get('command', '')
    print(cmd)
except:
    pass
" 2>/dev/null)
        if [ -n "$cmd" ]; then
            echo "$cmd"
            return
        fi
    fi

    local cmd=$(echo "$input" | grep -oP '(?<="command"\s*:\s*")[^"]*(?:\\.[^"]*)*' 2>/dev/null | head -1)
    if [ -n "$cmd" ]; then
        echo "$cmd"
        return
    fi

    cmd=$(echo "$input" | awk -F'"command"[[:space:]]*:[[:space:]]*"' '{
        if (NF > 1) {
            result = $2
            while (match(result, /\\."/) == 0 && index(result, "\"") > 0) {
                result = substr(result, 1, index(result, "\"")-1)
            }
            gsub(/\\\"/, "\"", result)
            gsub(/\\\\/, "\\", result)
            print result
            exit
        }
    }' 2>/dev/null)
    echo "$cmd"
}

# 从命令中提取目标路径
extract_target_paths() {
    local cmd="$1"
    # 提取看起来像路径的参数
    echo "$cmd" | grep -oE '(/[a-zA-Z0-9_/.-]+|~/[a-zA-Z0-9_/.-]+|\./[a-zA-Z0-9_/.-]+|[a-zA-Z0-9_-]+\.[a-zA-Z0-9_.-]+)' 2>/dev/null | head -10
}

# 记录待删除项
record_pending_deletion() {
    local cmd="$1"
    local reason="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # 提取目标路径
    local paths=$(extract_target_paths "$cmd")

    # 追加到文本文件
    {
        echo "[$timestamp] $reason"
        echo "  命令: $cmd"
        if [ -n "$paths" ]; then
            echo "  目标: $paths"
        fi
        echo ""
    } >> "$PENDING_DELETIONS_FILE"

    # 追加到 JSON 文件（供程序读取）
    if command -v python3 &>/dev/null; then
        # 使用文件传递数据，避免转义问题
        local tmp_cmd=$(mktemp)
        local tmp_reason=$(mktemp)
        local tmp_paths=$(mktemp)

        echo "$cmd" > "$tmp_cmd"
        echo "$reason" > "$tmp_reason"
        echo "$paths" > "$tmp_paths"

        python3 << PYEOF
import json
import os

pending_file = "$PENDING_DELETIONS_JSON"
entries = []

if os.path.exists(pending_file):
    try:
        with open(pending_file, 'r') as f:
            entries = json.load(f)
    except:
        entries = []

# 从临时文件读取
with open("$tmp_cmd", 'r') as f:
    cmd = f.read().strip()
with open("$tmp_reason", 'r') as f:
    reason = f.read().strip()
with open("$tmp_paths", 'r') as f:
    paths_content = f.read().strip()

entries.append({
    "timestamp": "$timestamp",
    "command": cmd,
    "reason": reason,
    "paths": paths_content.split() if paths_content else []
})

with open(pending_file, 'w') as f:
    json.dump(entries, f, indent=2, ensure_ascii=False)

# 清理临时文件
os.remove("$tmp_cmd")
os.remove("$tmp_reason")
os.remove("$tmp_paths")
PYEOF
    fi
}

# 显示汇总并请求用户确认
show_summary_and_confirm() {
    local cmd="$1"
    local reason="$2"

    cat >&2 << EOF

╔══════════════════════════════════════════════════════════════════════╗
║                     ⚠️  检测到删除操作                               ║
╠══════════════════════════════════════════════════════════════════════╣
║                                                                      ║
║  拦截原因: $reason
║                                                                      ║
║  尝试执行的命令:                                                     ║
║    $cmd
║                                                                      ║
╠══════════════════════════════════════════════════════════════════════╣
║                                                                      ║
║  📋 此操作已被记录到待删除列表                                       ║
║                                                                      ║
║  查看待删除内容:                                                     ║
║    cat $PENDING_DELETIONS_FILE
║                                                                      ║
║  清空待删除列表:                                                     ║
║    rm $PENDING_DELETIONS_FILE $PENDING_DELETIONS_JSON
║                                                                      ║
╠══════════════════════════════════════════════════════════════════════╣
║                                                                      ║
║  💡 建议操作流程:                                                    ║
║     1. 继续当前任务，让 Agent 跳过删除步骤                           ║
║     2. 任务完成后，查看待删除列表                                    ║
║     3. 用户手动确认并执行删除                                        ║
║                                                                      ║
╚══════════════════════════════════════════════════════════════════════╝

EOF
}

COMMAND=$(extract_command "$INPUT")
log_debug "提取的命令: $COMMAND"

if [ -z "$COMMAND" ]; then
    log_debug "无命令，允许执行"
    exit 0
fi

# ============================================
# 危险命令模式定义
# ============================================

check_dangerous() {
    local cmd="$1"

    # 1. 直接 rm 调用
    if echo "$cmd" | grep -qE '(^|[[:space:];/\\])rm([[:space:]]|$)'; then
        echo "直接调用 rm 命令"
        return 0
    fi

    # 2. Shell 绕过方式
    if echo "$cmd" | grep -qE '(sh|bash|dash|zsh|ksh|fish)\s+-c.*\brm\b'; then
        echo "通过 Shell -c 调用 rm"
        return 0
    fi

    # 3. exec 命令
    if echo "$cmd" | grep -qE '\bexec\s+.*\brm\b'; then
        echo "通过 exec 调用 rm"
        return 0
    fi

    # 4. find 命令删除
    if echo "$cmd" | grep -qE '\bfind\b.*(-delete|-exec\s+rm|execdir\s+rm|\|\s*xargs\s+rm)'; then
        echo "通过 find 命令删除文件"
        return 0
    fi

    # 5. xargs rm (确保 rm 是独立命令，不是字符串的一部分如 "rm-pending")
    # rm 后面必须是空格或行尾，不能是连字符或字母（排除 rm-pending, rmtree 等）
    if echo "$cmd" | grep -qE '\bxargs\b.*\brm[[:space:]]|\bxargs\b.*\brm$'; then
        echo "通过 xargs 调用 rm"
        return 0
    fi

    # 6. Python 删除操作
    if echo "$cmd" | grep -qE 'python[23]?[[:space:]]+(-c|<<).*os\.(remove|unlink|rmdir)'; then
        echo "通过 Python 删除文件"
        return 0
    fi
    if echo "$cmd" | grep -qE 'python[23]?[[:space:]]+(-c|<<).*shutil\.rmtree'; then
        echo "通过 Python shutil.rmtree 删除目录"
        return 0
    fi

    # 7. Perl unlink
    if echo "$cmd" | grep -qE 'perl[[:space:]]+(-e|<<).*unlink'; then
        echo "通过 Perl unlink 删除"
        return 0
    fi

    # 8. Ruby File.delete
    if echo "$cmd" | grep -qE 'ruby\s+(-e|<<).*\b(File\.delete|FileUtils\.rm)\b'; then
        echo "通过 Ruby 删除文件"
        return 0
    fi

    # 9. Node.js fs 删除
    if echo "$cmd" | grep -qE "node[[:space:]]+(-e|<<).*(unlinkSync|unlink|rmSync|rmdirSync)"; then
        echo "通过 Node.js 删除文件"
        return 0
    fi

    # 10. 环境变量命令调用
    if echo "$cmd" | grep -qE '\b(env|nice|nohup|timeout|ionice|strace|taskset)\s+.*\brm\b'; then
        echo "通过包装命令调用 rm"
        return 0
    fi

    # 11. busybox rm
    if echo "$cmd" | grep -qE '\bbusybox\s+rm\b'; then
        echo "通过 busybox 调用 rm"
        return 0
    fi

    # 12. unlink 命令
    if echo "$cmd" | grep -qE '(^|[[:space:]])unlink([[:space:]]|$)'; then
        echo "使用 unlink 命令"
        return 0
    fi

    # 13. shred 命令
    if echo "$cmd" | grep -qE '\bshred\b.*(-u|--remove)'; then
        echo "通过 shred 删除文件"
        return 0
    fi

    # 14. wipe 命令
    if echo "$cmd" | grep -qE '(^|[[:space:]])wipe([[:space:]]|$)'; then
        echo "使用 wipe 命令"
        return 0
    fi

    # 15. truncate 命令
    if echo "$cmd" | grep -qE '\btruncate\b.*-s\s+0'; then
        echo "通过 truncate 清空文件"
        return 0
    fi

    # 16. tar --remove-files
    if echo "$cmd" | grep -qE '\btar\b.*--remove-files'; then
        echo "通过 tar --remove-files 删除"
        return 0
    fi

    # 17. gzip/bzip2/xz 删除原文件
    if echo "$cmd" | grep -qE '\b(gzip|bzip2|xz|lzma)\b.*[^-k]'; then
        if echo "$cmd" | grep -qvE '\b(gzip|bzip2|xz|lzma)\b.*-k'; then
            if ! echo "$cmd" | grep -qE -- '-k|--keep'; then
                echo "通过压缩命令删除原文件"
                return 0
            fi
        fi
    fi

    # 18. 命令替换绕过
    if echo "$cmd" | grep -qE '\$\((which|type|command)\s+.*rm\)|`(which|type|command)\s+.*rm`'; then
        echo "通过命令替换调用 rm"
        return 0
    fi

    # 19. install 命令覆盖
    if echo "$cmd" | grep -qE '\binstall\s+/dev/null'; then
        echo "通过 install 覆盖文件"
        return 0
    fi

    # 20. mv 到 /dev/null
    if echo "$cmd" | grep -qE '\bmv\s+.*\s+/dev/null'; then
        echo "尝试 mv 文件到 /dev/null"
        return 0
    fi

    # 21. dd 覆盖删除（用 /dev/null 清空文件，支持参数顺序交换）
    if echo "$cmd" | grep -qE '\bdd\b.*(if=/dev/null.*of=|of=.*if=/dev/null)'; then
        echo "通过 dd 覆盖文件"
        return 0
    fi

    # 22. cp /dev/null 覆盖
    if echo "$cmd" | grep -qE '\bcp\s+/dev/null\s+'; then
        echo "通过 cp /dev/null 覆盖文件"
        return 0
    fi

    # 23. grm (GNU coreutils)
    if echo "$cmd" | grep -qE '(^|[[:space:]])grm([[:space:]]|$)'; then
        echo "使用 grm 命令"
        return 0
    fi

    # 24. g rm (GNU coreutils 前缀)
    if echo "$cmd" | grep -qE '\bg\s+rm\b'; then
        echo "使用 g rm 命令"
        return 0
    fi

    # 25. 检测通过 eval 构造调用 rm（echo/printf 本身不会执行命令）
    if echo "$cmd" | grep -qE '\beval\b.*["'\''].*\brm([[:space:]]|$)'; then
        echo "通过 eval 构造调用 rm"
        return 0
    fi

    # 26. 执行已知包含危险命令的脚本文件
    # 检查是否在执行 .sh 文件或已知被标记的脚本
    if echo "$cmd" | grep -qE '(bash|sh|zsh|ksh|fish|source|\.)\s+.*\.sh'; then
        # 提取脚本路径
        local script_path=$(echo "$cmd" | grep -oE '[^[:space:]]+\.sh' | head -1)
        if [ -n "$script_path" ] && [ -f "$script_path" ]; then
            # 安全白名单：只允许特定插件目录（使用完整路径匹配，防止路径混淆攻击）
            local real_path=$(readlink -f "$script_path" 2>/dev/null || echo "$script_path")
            if [[ "$real_path" == *"/rm-security-claude-plugin/"* ]] || \
               [[ "$real_path" == *"/.claude/plugins/cache/rm-security-plugin/"* ]] || \
               [[ "$real_path" == *"/.claude/hooks/scripts/rm-"* ]]; then
                : # 跳过检查 - 只允许这些特定路径模式
            # 检查脚本内容是否包含危险命令（排除注释和字符串中的提示）
            elif grep -qE '^[^#]*\brm([[:space:]]|$)|os\.(remove|unlink|rmdir)|shutil\.rmtree|unlink\(' "$script_path" 2>/dev/null; then
                echo "执行包含删除命令的脚本: $script_path"
                return 0
            fi
        fi
    fi

    # 27. 执行 Python 脚本检查
    if echo "$cmd" | grep -qE 'python[23]?\s+.*\.py'; then
        local script_path=$(echo "$cmd" | grep -oE '[^[:space:]]+\.py' | head -1)
        if [ -n "$script_path" ] && [ -f "$script_path" ]; then
            # 安全白名单：使用完整路径匹配和符号链接解析
            local real_path=$(readlink -f "$script_path" 2>/dev/null || echo "$script_path")
            if [[ "$real_path" == *"/rm-security-claude-plugin/"* ]] || \
               [[ "$real_path" == *"/.claude/plugins/cache/rm-security-plugin/"* ]] || \
               [[ "$real_path" == *"/.claude/hooks/scripts/rm-"* ]] || \
               [[ "$real_path" == *"/test-rm-security"* ]]; then
                : # 跳过检查 - 只允许这些特定路径模式
            elif grep -qE 'os\.(remove|unlink|rmdir)|shutil\.rmtree' "$script_path" 2>/dev/null; then
                echo "执行包含删除操作的 Python 脚本: $script_path"
                return 0
            fi
        fi
    fi

    return 1
}

# 执行检查
DANGER_REASON=$(check_dangerous "$COMMAND" 2>/dev/null || true)

if [ -n "$DANGER_REASON" ]; then
    log_debug "拦截原因: $DANGER_REASON"

    # 记录待删除项
    record_pending_deletion "$COMMAND" "$DANGER_REASON"

    # 显示汇总信息
    show_summary_and_confirm "$COMMAND" "$DANGER_REASON"

    # Exit code 2 = 阻止工具执行
    exit 2
fi

# 允许执行
log_debug "命令安全，允许执行"
exit 0
