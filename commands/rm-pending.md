---
name: rm-pending
description: 管理待删除文件列表 - 查看、执行或清空被拦截的删除操作
---

# 待删除列表管理

查看和管理被拦截的删除操作列表。

## 用法

```bash
# 查看待删除列表
/命令: rm-pending list

# 以 JSON 格式输出
/命令: rm-pending json

# 执行删除（交互式确认）
/命令: rm-pending exec

# 清空列表
/命令: rm-pending clear
```

## 操作

请执行以下操作：

1. 运行命令查看当前待删除列表：
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/hooks/scripts/rm-pending.sh list
   ```

2. 根据用户需求选择：
   - `list` - 查看列表
   - `json` - JSON 格式输出
   - `exec` - 交互式执行
   - `clear` - 清空列表
