# Claude Skills Collection

> 个人 Claude Code 技能集合，版本控制于 Git

## 📁 技能列表

| 技能名称 | 描述 | 目录 |
|---------|------|------|
| **paper-fetcher** | 从自然语言文本中智能识别论文并批量下载 PDF | [paper-fetcher/](./paper-fetcher/) |

## 🚀 使用方式

此仓库通过符号链接连接到 `~/.claude/skills/`，Claude Code 可以直接调用：

```bash
~/.claude/skills -> ~/Desktop/projects/skills
```

## ➕ 添加新技能

1. 创建新技能目录
2. 包含必需文件：`SKILL.md`（技能定义）
3. 提交到 Git
4. Claude Code 会自动识别（通过符号链接）

### 技能目录结构

```
your-skill/
├── SKILL.md          # 必需：技能定义文件
├── README.md         # 技能说明文档
├── scripts/          # 辅助脚本
│   └── ...
└── examples.md       # 使用示例（可选）
```

## 🔄 工作流程

```bash
# 修改技能
cd ~/Desktop/projects/skills/paper-fetcher

# 提交更改
git add .
git commit -m "feat: improve search algorithm"
git push
```

---

**创建时间**: 2026-03-01
**维护者**: Jerry
