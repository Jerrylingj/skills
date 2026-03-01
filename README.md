# Claude Skills Collection

个人自用的 claude code skills

## 📁 技能列表

| 技能名称 | 描述 | 目录 |
|---------|------|------|
| **paper-fetcher** | 从自然语言文本中智能识别论文并批量下载 PDF | [paper-fetcher/](./paper-fetcher/) |

## 🚀 快速开始

### 1. 克隆仓库

```bash
git clone https://github.com/YOUR_USERNAME/skills.git
cd skills
```

### 2. 安装技能

运行安装脚本，会自动在 `~/.claude/skills/` 下创建符号链接：

```bash
# 安装全部技能（一键）
bash install.sh

# 或只安装某个技能
bash install.sh install paper-fetcher
```

### 3. 开始使用

安装完成后，Claude Code 会自动识别已链接的技能，直接在对话中调用即可。

### 其他命令

```bash
bash install.sh list                 # 查看可用技能及安装状态
bash install.sh status               # 显示配置信息
bash install.sh uninstall            # 移除全部技能
bash install.sh uninstall paper-fetcher  # 移除单个技能
```

> **原理**：脚本在 `~/.claude/skills/` 中为每个技能创建独立的符号链接（如 `~/.claude/skills/paper-fetcher → <你的仓库>/paper-fetcher`），不会影响你已有的其他技能。

## ➕ 添加新技能

1. 创建新技能目录
2. 包含必需文件：`SKILL.md`（技能定义）
3. 运行 `bash install.sh install <技能名>` 链接新技能

### 技能目录结构

```
your-skill/
├── SKILL.md          # 必需：技能定义文件
├── README.md         # 技能说明文档
├── scripts/          # 辅助脚本
│   └── ...
└── examples.md       # 使用示例（可选）
```

符号链接指向的是本地仓库目录，所以 `git pull` 更新后技能立即生效，无需重新安装。
