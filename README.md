# rm-security-claude-plugin

Claude Code 安全插件 - 拦截 rm 删除操作，保护系统安全

## 功能特性

- 🔒 **全面拦截**：拦截 25+ 种 rm 逃逸方式
- 📋 **记录管理**：删除操作记录到待删除列表
- 🔍 **脚本检测**：检测写入的脚本内容是否包含危险命令
- ✅ **用户确认**：任务完成后由用户确认并执行删除

## 安装方法

### 方法1：本地安装

```bash
# 克隆或复制到 Claude 插件目录
cp -r rm-security-claude-plugin ~/.claude/plugins/local/

# 重启 Claude Code 生效
```

### 方法2：配置文件引用

在 `~/.claude/settings.json` 中添加：

```json
{
  "plugins": {
    "directories": [
      "/path/to/rm-security-claude-plugin"
    ]
  }
}
```

## 使用方法

### 查看待删除列表

```bash
# 在 Claude Code 中使用命令
/rm-pending list
```

### 清空列表

```bash
/rm-pending clear
```

### 执行删除

```bash
/rm-pending exec
```

## 拦截覆盖

| 类型 | 命令示例 |
|------|----------|
| 直接调用 | `rm -rf /path` |
| Shell 绕过 | `bash -c 'rm ...'` |
| Python | `os.remove()`, `shutil.rmtree()` |
| Perl | `unlink` |
| Node.js | `fs.unlinkSync()` |
| find | `find -delete`, `find -exec rm` |
| 包装命令 | `env rm`, `nice rm` |
| 脚本执行 | `bash script.sh` |

## 文件结构

```
rm-security-claude-plugin/
├── .claude-plugin/
│   └── plugin.json          # 插件配置
├── hooks/
│   ├── hooks.json           # Hook 配置
│   └── scripts/
│       ├── rm-interceptor.sh        # Bash 命令拦截
│       ├── script-content-checker.sh # 脚本内容检测
│       └── rm-pending.sh            # 列表管理
├── commands/
│   └── rm-pending.md        # 命令定义
├── skills/
│   └── rm-security/
│       └── SKILL.md         # 技能说明
├── marketplace.json         # 市场配置
└── README.md               # 说明文档
```

## 测试

### 方法1：使用提示词测试

使用以下提示词测试插件功能：

```
请帮我清理 /tmp 目录下的所有 .tmp 文件
```

预期行为：删除操作被拦截，记录到待删除列表。

### 方法2：运行测试脚本

```bash
# 设置插件根目录变量
export CLAUDE_PLUGIN_ROOT="$(pwd)"

# 运行 Hook 测试
./tests/test-hook.sh

# 运行完整安全测试
./tests/test-rm-security.sh
```

### 测试覆盖

- ✅ 直接 rm 调用
- ✅ Shell 绕过 (bash -c, sh -c)
- ✅ 脚本语言 (Python, Perl, Node.js)
- ✅ find 命令删除
- ✅ 包装命令 (env, nice, nohup)
- ✅ 替代命令 (unlink, shred, busybox)
- ✅ 其他危险操作 (tar, truncate, mv)

## 许可证

MIT
