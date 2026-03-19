#!/bin/bash
# rm 安全测试套件
# 测试各种 rm 逃逸方式是否被成功阻止
# 用法: ./test-rm-security.sh

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 测试计数器
TOTAL=0
PASSED=0
FAILED=0

# 测试目录
TEST_DIR="/tmp/rm-security-test-$$"

# 初始化测试环境
setup() {
    mkdir -p "$TEST_DIR"
    echo "测试环境已创建: $TEST_DIR"
}

# 清理测试环境
cleanup() {
    if [ -d "$TEST_DIR" ]; then
        # 使用 root 权限清理（如果需要）
        sudo rm -rf "$TEST_DIR" 2>/dev/null || true
    fi
    echo "测试环境已清理"
}

# 测试函数
# 参数1: 测试名称
# 参数2: 要执行的命令
# 参数3: 期望结果 (blocked=应该被阻止, allowed=应该允许)
run_test() {
    local name="$1"
    local cmd="$2"
    local expected="$3"

    TOTAL=$((TOTAL + 1))

    # 创建测试文件
    echo "test content" > "$TEST_DIR/testfile_$TOTAL.txt"

    echo -e "\n${YELLOW}[测试 $TOTAL]${NC} $name"
    echo "命令: $cmd"

    # 执行命令，捕获输出和退出码
    set +e
    output=$(eval "$cmd" 2>&1)
    exit_code=$?
    set -e

    # 检查文件是否仍然存在
    file_exists="no"
    if [ -f "$TEST_DIR/testfile_$TOTAL.txt" ]; then
        file_exists="yes"
    fi

    # 判断测试结果
    if [ "$expected" = "blocked" ]; then
        if [ "$file_exists" = "yes" ]; then
            echo -e "${GREEN}✓ 通过${NC} - 文件未被删除（被阻止）"
            PASSED=$((PASSED + 1))
        else
            echo -e "${RED}✗ 失败${NC} - 文件被删除了（逃逸成功！）"
            echo "输出: $output"
            FAILED=$((FAILED + 1))
        fi
    else
        if [ "$file_exists" = "no" ]; then
            echo -e "${GREEN}✓ 通过${NC} - 文件已删除（如预期）"
            PASSED=$((PASSED + 1))
        else
            echo -e "${RED}✗ 失败${NC} - 文件未删除"
            echo "输出: $output"
            FAILED=$((FAILED + 1))
        fi
    fi
}

# 主测试流程
main() {
    echo "========================================"
    echo "       rm 安全测试套件"
    echo "========================================"
    echo "测试目标: 验证 rm 命令已被安全限制"
    echo "执行时间: $(date)"
    echo ""

    setup

    echo ""
    echo "========================================"
    echo "第一部分: 直接调用测试"
    echo "========================================"

    # 测试1: 直接调用 rm
    run_test "直接调用 rm" \
        "rm $TEST_DIR/testfile_*.txt" \
        "blocked"

    # 测试2: 使用完整路径
    run_test "使用 /bin/rm 完整路径" \
        "/bin/rm $TEST_DIR/testfile_*.txt" \
        "blocked"

    # 测试3: 使用 /usr/bin/rm
    run_test "使用 /usr/bin/rm 路径" \
        "/usr/bin/rm $TEST_DIR/testfile_*.txt" \
        "blocked"

    echo ""
    echo "========================================"
    echo "第二部分: Shell 绕过测试"
    echo "========================================"

    # 测试4: 通过 sh -c 调用
    run_test "通过 sh -c 调用 rm" \
        "sh -c 'rm $TEST_DIR/testfile_*.txt'" \
        "blocked"

    # 测试5: 通过 bash -c 调用
    run_test "通过 bash -c 调用 rm" \
        "bash -c 'rm $TEST_DIR/testfile_*.txt'" \
        "blocked"

    # 测试6: 通过 dash 调用
    run_test "通过 dash -c 调用 rm" \
        "dash -c 'rm $TEST_DIR/testfile_*.txt'" \
        "blocked"

    # 测试7: 通过 zsh 调用（如果存在）
    if command -v zsh &>/dev/null; then
        run_test "通过 zsh -c 调用 rm" \
            "zsh -c 'rm $TEST_DIR/testfile_*.txt'" \
            "blocked"
    fi

    # 测试8: 通过 exec 命令
    run_test "通过 exec 调用 rm" \
        "bash -c 'exec rm $TEST_DIR/testfile_*.txt'" \
        "blocked"

    echo ""
    echo "========================================"
    echo "第三部分: find 命令绕过测试"
    echo "========================================"

    # 测试9: find -delete
    run_test "通过 find -delete 删除" \
        "find $TEST_DIR -name 'testfile_*.txt' -delete" \
        "blocked"

    # 测试10: find -exec rm
    run_test "通过 find -exec rm 删除" \
        "find $TEST_DIR -name 'testfile_*.txt' -exec rm {} \;" \
        "blocked"

    # 测试11: find | xargs rm
    run_test "通过 find | xargs rm 删除" \
        "find $TEST_DIR -name 'testfile_*.txt' | xargs rm" \
        "blocked"

    # 测试12: find -execdir rm
    run_test "通过 find -execdir rm 删除" \
        "find $TEST_DIR -name 'testfile_*.txt' -execdir rm {} \;" \
        "blocked"

    echo ""
    echo "========================================"
    echo "第四部分: 脚本语言绕过测试"
    echo "========================================"

    # 测试13: Python os.remove
    if command -v python3 &>/dev/null; then
        run_test "通过 Python os.remove 删除" \
            "python3 -c \"import os; os.remove('$TEST_DIR/testfile_*.txt')\"" \
            "blocked"
    fi

    # 测试14: Python os.unlink
    if command -v python3 &>/dev/null; then
        run_test "通过 Python os.unlink 删除" \
            "python3 -c \"import os; os.unlink('$TEST_DIR/testfile_*.txt')\"" \
            "blocked"
    fi

    # 测试15: Python shutil.rmtree (目录)
    if command -v python3 &>/dev/null; then
        mkdir -p "$TEST_DIR/testdir_$$"
        run_test "通过 Python shutil.rmtree 删除目录" \
            "python3 -c \"import shutil; shutil.rmtree('$TEST_DIR/testdir_$$')\"" \
            "blocked"
    fi

    # 测试16: Perl unlink
    if command -v perl &>/dev/null; then
        run_test "通过 Perl unlink 删除" \
            "perl -e \"unlink '$TEST_DIR/testfile_*.txt'\"" \
            "blocked"
    fi

    # 测试17: Ruby File.delete
    if command -v ruby &>/dev/null; then
        run_test "通过 Ruby File.delete 删除" \
            "ruby -e \"File.delete('$TEST_DIR/testfile_*.txt')\"" \
            "blocked"
    fi

    # 测试18: Node.js fs.unlink
    if command -v node &>/dev/null; then
        run_test "通过 Node.js fs.unlinkSync 删除" \
            "node -e \"require('fs').unlinkSync('$TEST_DIR/testfile_*.txt')\"" \
            "blocked"
    fi

    echo ""
    echo "========================================"
    echo "第五部分: 其他命令绕过测试"
    echo "========================================"

    # 测试19: xargs 直接调用
    run_test "通过 xargs rm 删除" \
        "echo '$TEST_DIR/testfile_*.txt' | xargs rm" \
        "blocked"

    # 测试20: env 命令调用
    run_test "通过 env rm 删除" \
        "env rm $TEST_DIR/testfile_*.txt" \
        "blocked"

    # 测试21: nice 命令调用
    run_test "通过 nice rm 删除" \
        "nice rm $TEST_DIR/testfile_*.txt" \
        "blocked"

    # 测试22: nohup 命令调用
    run_test "通过 nohup rm 删除" \
        "nohup rm $TEST_DIR/testfile_*.txt 2>/dev/null" \
        "blocked"

    # 测试23: timeout 命令调用
    run_test "通过 timeout rm 删除" \
        "timeout 5 rm $TEST_DIR/testfile_*.txt" \
        "blocked"

    # 测试24: ionice 命令调用
    run_test "通过 ionice rm 删除" \
        "ionice rm $TEST_DIR/testfile_*.txt" \
        "blocked"

    # 测试25: strace 命令调用
    if command -v strace &>/dev/null; then
        run_test "通过 strace rm 删除" \
            "strace -e none rm $TEST_DIR/testfile_*.txt 2>/dev/null" \
            "blocked"
    fi

    echo ""
    echo "========================================"
    echo "第六部分: busybox 和替代命令测试"
    echo "========================================"

    # 测试26: busybox rm（如果存在）
    if command -v busybox &>/dev/null; then
        run_test "通过 busybox rm 删除" \
            "busybox rm $TEST_DIR/testfile_*.txt" \
            "blocked"
    fi

    # 测试27: unlink 命令
    if command -v unlink &>/dev/null; then
        run_test "通过 unlink 命令删除" \
            "unlink $TEST_DIR/testfile_*.txt" \
            "blocked"
    fi

    # 测试28: shred 命令（安全删除）
    if command -v shred &>/dev/null; then
        run_test "通过 shred 删除" \
            "shred -u $TEST_DIR/testfile_*.txt" \
            "blocked"
    fi

    # 测试29: wipe 命令（如果存在）
    if command -v wipe &>/dev/null; then
        run_test "通过 wipe 删除" \
            "wipe -f $TEST_DIR/testfile_*.txt" \
            "blocked"
    fi

    echo ""
    echo "========================================"
    echo "第七部分: 文件操作替代测试"
    echo "========================================"

    # 测试30: mv 到 /dev/null
    run_test "通过 mv 到 /dev/null" \
        "mv $TEST_DIR/testfile_*.txt /dev/null 2>/dev/null || true" \
        "blocked"

    # 测试31: 重定向清空文件（不删除但清空内容）
    echo "test" > "$TEST_DIR/testfile_clear.txt"
    echo -e "\n${YELLOW}[测试]${NC} 重定向清空文件内容"
    echo ": > $TEST_DIR/testfile_clear.txt"
    : > "$TEST_DIR/testfile_clear.txt"
    if [ -f "$TEST_DIR/testfile_clear.txt" ] && [ ! -s "$TEST_DIR/testfile_clear.txt" ]; then
        echo -e "${YELLOW}⚠ 注意${NC} - 文件被清空但未删除（这是允许的行为）"
    fi

    # 测试32: dd 清空文件
    echo "test" > "$TEST_DIR/testfile_dd.txt"
    run_test "通过 dd 清空并删除" \
        "dd if=/dev/null of=$TEST_DIR/testfile_dd.txt 2>/dev/null" \
        "blocked"

    echo ""
    echo "========================================"
    echo "第八部分: 进程和系统调用测试"
    echo "========================================"

    # 测试33: cp /dev/null 覆盖
    echo "test" > "$TEST_DIR/testfile_cp.txt"
    run_test "通过 cp /dev/null 覆盖" \
        "cp /dev/null $TEST_DIR/testfile_cp.txt" \
        "blocked"

    # 测试34: truncate 命令
    if command -v truncate &>/dev/null; then
        echo "test" > "$TEST_DIR/testfile_truncate.txt"
        run_test "通过 truncate 清空文件" \
            "truncate -s 0 $TEST_DIR/testfile_truncate.txt" \
            "blocked"
    fi

    # 测试35: install 命令覆盖
    if command -v install &>/dev/null; then
        run_test "通过 install 覆盖文件" \
            "install /dev/null $TEST_DIR/testfile_*.txt" \
            "blocked"
    fi

    echo ""
    echo "========================================"
    echo "第九部分: 归档命令测试"
    echo "========================================"

    # 测试36: tar 删除原文件
    run_test "通过 tar --remove-files 删除" \
        "tar --remove-files -cf /dev/null $TEST_DIR/testfile_*.txt 2>/dev/null || true" \
        "blocked"

    # 测试37: gzip 删除原文件
    if command -v gzip &>/dev/null; then
        run_test "通过 gzip 删除原文件" \
            "gzip -f $TEST_DIR/testfile_*.txt && gunzip $TEST_DIR/testfile_*.txt.gz" \
            "blocked"
    fi

    echo ""
    echo "========================================"
    echo "第十部分: GNU coreutils 别名测试"
    echo "========================================"

    # 测试38: 通过 coreutils 的 grm（如果存在）
    if command -v grm &>/dev/null; then
        run_test "通过 grm 删除" \
            "grm $TEST_DIR/testfile_*.txt" \
            "blocked"
    fi

    # 测试39: 通过命令替换
    run_test "通过 \$(which rm) 删除" \
        "\$(which rm) $TEST_DIR/testfile_*.txt" \
        "blocked"

    # 测试40: 通过 type 命令获取路径
    run_test "通过 \$(type -p rm) 删除" \
        "\$(type -p rm) $TEST_DIR/testfile_*.txt" \
        "blocked"

    echo ""
    echo "========================================"
    echo "              测试总结"
    echo "========================================"
    echo -e "总测试数: ${TOTAL}"
    echo -e "通过: ${GREEN}${PASSED}${NC}"
    echo -e "失败: ${RED}${FAILED}${NC}"
    echo ""

    if [ $FAILED -eq 0 ]; then
        echo -e "${GREEN}✓ 所有测试通过！rm 限制有效。${NC}"
    else
        echo -e "${RED}✗ 存在 $FAILED 个安全漏洞！${NC}"
        echo "请检查失败的测试用例并修复问题。"
    fi

    cleanup

    exit $FAILED
}

# 捕获退出信号
trap cleanup EXIT

# 运行主函数
main "$@"
