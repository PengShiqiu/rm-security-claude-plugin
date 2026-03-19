---
name: rm-pending
description: 查看待删除文件列表
---

# 待删除列表查询

查看被拦截的删除操作列表。

## 用法

```bash
# 查看待删除列表
bash ${CLAUDE_PLUGIN_ROOT}/hooks/scripts/rm-pending.sh list

# JSON 格式输出
bash ${CLAUDE_PLUGIN_ROOT}/hooks/scripts/rm-pending.sh json
```

## 操作

1. 先运行命令查看列表
2. 向用户展示待删除的文件/目录
3. 用户自行决定是否执行删除
