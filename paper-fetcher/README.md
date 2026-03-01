# Paper Fetcher Skill

从自然语言文本中智能识别论文标题，批量搜索、下载并分类整理 PDF 的 Claude Code 技能。

## 功能特性

- 🧠 智能识别：从自由格式文本中提取论文标题
- 🔍 多源搜索：arXiv → Semantic Scholar → DBLP（按优先级回退）
- ⬇️ 批量下载：统一下载，自动重试
- ✅ 内容验证：提取 PDF 文本，LLM 语义判断是否为目标论文
- 📁 智能分类：根据用户输入自动分类整理到桌面
- 📊 下载报告：生成 README.md 汇总下载结果

## 安装

通过仓库根目录的安装脚本链接：

```bash
# 在仓库根目录执行
bash install.sh install paper-fetcher
```

安装后技能位于：
```
~/.claude/skills/paper-fetcher/
```

## 使用方法

在 Claude Code 中直接调用：

```bash
# 从论文列表批量下载
/paper-fetcher 帮我下载以下论文：
- Attention Is All You Need
- BERT: Pre-training of Deep Bidirectional Transformers
- GPT-4 Technical Report

# 从自然语言描述提取
/paper-fetcher 我在看一篇关于 LLM Memory 的 survey，提到了 A-MEM, MemGPT, SCM 这几篇论文，帮我下载

# 带分类的论文集
/paper-fetcher 下载以下论文，已经分好类了：
## CV
ResNet, ViT
## NLP
BERT, GPT-3
```

## 文件结构

```
paper-fetcher/
├── SKILL.md                         # 技能定义（核心工作流）
├── README.md                        # 本文件
├── examples.md                      # 使用示例
└── scripts/
    ├── batch-search.sh              # 批量搜索所有论文
    ├── batch-download.sh            # 批量下载所有论文
    ├── batch-verify.sh              # 批量验证所有 PDF 内容
    ├── search-arxiv.sh              # arXiv API 搜索
    ├── search-semantic-scholar.sh   # Semantic Scholar API 搜索
    ├── search-dblp.sh               # DBLP API 搜索
    ├── search-github.sh             # GitHub 仓库搜索
    ├── download-paper.sh            # 统一下载脚本（arXiv/OpenReview/URL）
    ├── verify-pdf.sh                # PDF 格式验证
    └── extract-pdf-text.sh          # PDF 文本提取（内容验证用）
```

## 工作流程

```
输入文本 → 识别论文 → 批量搜索 → 批量下载 → 批量验证 → WebSearch 补救 → 分类整理
```

1. **识别论文标题**：从用户文本中提取论文名、分类、年份等信息
2. **批量搜索**：`batch-search.sh` 搜索所有论文，自动回退 arXiv → Semantic Scholar → DBLP
3. **批量下载**：`batch-download.sh` 下载所有已找到的 PDF
4. **批量验证**：`batch-verify.sh` 提取 PDF 文本，LLM 语义审阅确认内容正确
5. **WebSearch 补救**：仅对搜索未找到或验证失败的论文使用 WebSearch 兜底
6. **整理 & 报告**：分类整理到 `~/Desktop/{topic}/`，生成 README.md 报告

## 输出结构示例

```
~/Desktop/LLM_Memory/
├── README.md                      # 下载报告
├── Memory_Mechanisms/
│   ├── 01_A-MEM.pdf
│   └── 02_MemGPT.pdf
└── Memory_Architectures/
    └── 01_SCM.pdf
```

## 支持的论文来源

| 来源 | 方式 | 说明 |
|------|------|------|
| arXiv | API + 直接下载 | CS 论文首选来源 |
| Semantic Scholar | API 搜索 | 跨学科论文元数据 |
| DBLP | API 搜索 | 计算机科学文献索引 |
| OpenReview | 直接下载 | 顶会论文（NeurIPS, ICLR 等） |
| 其他 URL | 直接下载 | 任意公开 PDF 链接 |

## 注意事项

- 仅从合法公开来源下载（arXiv、OpenReview 等）
- 论文名称支持模糊匹配，不需要完全精确
- 下载失败的论文会在报告中标注
- arXiv API 有频率限制，大批量下载时脚本会自动限流
