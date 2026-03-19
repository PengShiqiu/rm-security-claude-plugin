---
name: rm-security
description: rm 安全拦截系统 - 删除操作被拦截时自动激活
---

# rm 安全拦截系统

## 触发条件

Agent 尝试执行删除命令时自动激活。

## 拦截范围

- 直接删除: `rm`, `/bin/rm`
- Shell 绕过: `sh -c 'rm'`, `bash -c 'rm'`, `exec rm`
- 脚本语言: Python `os.remove()`, Perl `unlink`, Node `fs.unlinkSync()`
- 其他: `find -delete`, `xargs rm`, `env rm`

## 工作流程

```
Agent 尝试删除 → Hook 拦截并记录 → 返回警告 → 任务完成后用户查看列表 → 用户手动执行
```

## 相关命令

查看待删除列表：
```bash
bash ${CLAUDE_PLUGIN_ROOT}/hooks/scripts/rm-pending.sh list
```

## 注意

1. 删除操作被拦截后，Agent 可继续执行其他操作
2. 任务完成后用户自行确认是否删除
