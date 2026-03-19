#!/bin/bash
# test-hook.sh - 测试 rm-interceptor.sh 是否正常工作
# 用法: ./test-hook.sh

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Hook 脚本路径
HOOK_SCRIPT="${CLAUDE_PLUGIN_ROOT}/hooks/scripts/rm-interceptor.sh"

echo "========================================"
echo "    rm-interceptor.sh Hook 测试"
echo "========================================"
echo ""

# 使用 Python 构造 JSON（处理引号转义）
make_json() {
    python3 -c 'import json, sys; print(json.dumps({"tool_name": "Bash", "tool_input": {"command": sys.argv[1]}, "session_id": "test"}))' "$1"
}

# 测试函数
test_command() {
    local name="$1"
    local cmd="$2"
    local should_block="$3"

    # 构造 JSON 输入（使用 Python 处理转义）
    local json_input=$(make_json "$cmd")

    # 执行 hook 脚本
    set +e
    output=$(echo "$json_input" | bash "$HOOK_SCRIPT" 2>&1)
    exit_code=$?
    set -e

    # 判断结果
    if [ "$should_block" = "block" ]; then
        if [ $exit_code -eq 2 ]; then
            echo -e "${GREEN}✓${NC} $name - 正确拦截"
        else
            echo -e "${RED}✗${NC} $name - 应该被拦截但通过了 (exit: $exit_code)"
        fi
    else
        if [ $exit_code -eq 0 ]; then
            echo -e "${GREEN}✓${NC} $name - 正确放行"
        else
            echo -e "${RED}✗${NC} $name - 不应该被拦截 (exit: $exit_code)"
        fi
    fi
}

echo "测试直接 rm 调用..."
test_command "rm file.txt" "rm /tmp/test.txt" "block"
test_command "/bin/rm file.txt" "/bin/rm /tmp/test.txt" "block"
test_command "/usr/bin/rm file.txt" "/usr/bin/rm /tmp/test.txt" "block"

echo ""
echo "测试 Shell 绕过..."
test_command "bash -c rm" "bash -c 'rm /tmp/test.txt'" "block"
test_command "sh -c rm" "sh -c 'rm /tmp/test.txt'" "block"
test_command "exec rm" "bash -c 'exec rm /tmp/test.txt'" "block"

echo ""
echo "测试 find 命令..."
test_command "find -delete" "find /tmp -name test.txt -delete" "block"
test_command "find -exec rm" "find /tmp -name test.txt -exec rm {} \\;" "block"
test_command "find | xargs rm" "find /tmp -name test.txt | xargs rm" "block"

echo ""
echo "测试脚本语言..."
test_command "Python os.remove" "python3 -c \"import os; os.remove('/tmp/test.txt')\"" "block"
test_command "Python shutil.rmtree" "python3 -c \"import shutil; shutil.rmtree('/tmp/testdir')\"" "block"
test_command "Perl unlink" "perl -e \"unlink '/tmp/test.txt'\"" "block"
test_command "Node.js fs.unlink" "node -e \"require('fs').unlinkSync('/tmp/test.txt')\"" "block"

echo ""
echo "测试包装命令..."
test_command "env rm" "env rm /tmp/test.txt" "block"
test_command "nice rm" "nice rm /tmp/test.txt" "block"
test_command "nohup rm" "nohup rm /tmp/test.txt" "block"
test_command "timeout rm" "timeout 5 rm /tmp/test.txt" "block"

echo ""
echo "测试替代命令..."
test_command "unlink" "unlink /tmp/test.txt" "block"
test_command "shred -u" "shred -u /tmp/test.txt" "block"
test_command "busybox rm" "busybox rm /tmp/test.txt" "block"

echo ""
echo "测试其他危险操作..."
test_command "tar --remove-files" "tar --remove-files -cf /dev/null /tmp/test.txt" "block"
test_command "truncate -s 0" "truncate -s 0 /tmp/test.txt" "block"
test_command "mv to /dev/null" "mv /tmp/test.txt /dev/null" "block"

echo ""
echo "测试应该放行的命令..."
test_command "ls" "ls -la /tmp" "allow"
test_command "cat" "cat /tmp/test.txt" "allow"
test_command "echo" "echo hello" "allow"
test_command "git status" "git status" "allow"
test_command "npm install" "npm install" "allow"

echo ""
echo "========================================"
echo "测试完成！"
echo "========================================"
