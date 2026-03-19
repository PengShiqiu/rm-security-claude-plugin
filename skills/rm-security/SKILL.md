---
name: rm-security
description: rm 安全拦截系统 - 当 Agent 尝试删除文件时自动激活
---

# rm 安全拦截系统

## 触发条件

此技能在以下情况下自动激活：
- Agent 尝试执行 `rm` 命令
- Agent 尝试通过脚本语言删除文件
- Agent 尝试执行包含删除命令的脚本

## 功能说明

此插件会拦截所有删除操作，包括：

### 直接删除
- `rm`, `rm -rf`, `rm -r`
- `/bin/rm`, `/usr/bin/rm`

### Shell 绕过
- `sh -c 'rm ...'`
- `bash -c 'rm ...'`
- `exec rm`

### 脚本语言
- Python: `os.remove()`, `shutil.rmtree()`
- Perl: `unlink`
- Node.js: `fs.unlinkSync()`

### 其他方式
- `find -delete`
- `find -exec rm`
- `xargs rm`
- `env rm`, `nice rm`

## 工作流程

```
1. Agent 尝试删除
      ↓
2. Hook 拦截并记录
      ↓
3. Agent 收到警告，继续其他操作
      ↓
4. 任务完成后，用户查看列表
      ↓
5. 用户确认并手动执行
```

## 相关命令

- `/rm-pending list` - 查看待删除列表
- `/rm-pending exec` - 执行删除（需确认）
- `/rm-pending clear` - 清空列表

## 注意事项

1. 删除操作被拦截后，Agent 可以继续执行其他操作
2. 建议任务完成后统一确认删除
3. 所有删除操作都有记录，可追溯
