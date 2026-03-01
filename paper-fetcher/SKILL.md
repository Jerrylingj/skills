---
name: paper-fetcher
description: 从自然语言文本中智能识别论文并批量下载 PDF
allowed-tools: WebSearch, Bash, Write, Read, Grep, SubAgent
argument-hint: [text|file]
---

# Paper Fetcher

从用户提供的自然语言文本中，智能识别论文标题，搜索可下载链接，批量下载 PDF，并按类别整理到桌面。

---

## 整体工作流程

```
用户输入文本
  → Phase 1 [主Agent]: 识别论文标题，生成结构化 JSON
  → Phase 2 [Bash + LLM审阅]: batch-search.sh 批量搜索 + LLM 裁决低置信度候选
  → Phase 3 [Bash]: batch-download.sh 批量下载
  → Phase 4 [Bash + LLM审阅]: batch-verify.sh 文本提取 + LLM 语义验证
  → Phase 4b [WebSearch]: 针对未找到 / 错误论文的补救（可选）
  → Phase 5 [主Agent]: 整理分类，生成报告
```

### 设计原则
- **批量优先**：Phase 2, 3, 4 各通过一次批量脚本调用处理全部论文
- **自动容错**：批量脚本内部自动回退、重试，无需人工干预
- **按需补救**：仅对批量搜索无结果的论文，才用 WebSearch 兜底（Phase 4b）
- **LLM 驱动**：Phase 1 & 5 由主 Agent 直接执行（需要全局视角和语义理解能力）

---

## Phase 1: 识别论文标题

### 任务
从用户输入中提取所有论文信息，输出结构化列表。

### 规则
1. 使用 LLM 智能判断哪些是论文标题（不需要精确匹配）
2. 尊重用户意图：如果用户指定只处理某些领域/某些论文，只提取那些
3. 识别用户文本中是否包含**分类信息**（如标题分组、领域标签等）
4. 提取可能的辅助信息：作者、年份、arXiv ID、会议名等

### 结构化输出格式（内部使用）

```json
{
  "topic": "从用户文本推断的整体主题（用于文件夹命名）",
  "categories_detected": true,
  "papers": [
    {
      "id": 1,
      "title": "论文标题（尽可能完整）",
      "category": "类别名称（如果有）",
      "year": "年份（如果有）",
      "arxiv_hint": "文本中提及的 arXiv ID（如果有）",
      "authors_hint": "作者信息（如果有）"
    }
  ]
}
```

---

## Phase 2: 批量搜索论文链接

### 任务
将 Phase 1 输出的论文列表写入 JSON 文件，调用 `batch-search.sh` 一次性搜索所有论文。
脚本对高置信度匹配自动确认，对低置信度返回候选列表交由主 Agent（LLM）裁决。

### 操作步骤

#### Step 1: 写入论文列表 JSON

```bash
mkdir -p /tmp/paper-fetcher-tmp
cat > /tmp/paper-fetcher-tmp/papers.json << 'EOF'
[
  {"id": 1, "title": "Attention Is All You Need", "year": "2017", "hints": "Vaswani, Transformer"},
  {"id": 2, "title": "PREMem", "year": "2025", "hints": "episodic memory pre-storage reasoning"}
]
EOF
```

#### Step 2: 调用批量搜索

```bash
bash ~/.claude/skills/paper-fetcher/scripts/batch-search.sh /tmp/paper-fetcher-tmp/papers.json
```

脚本会自动:
- 依次对每篇论文搜索 arXiv API → Semantic Scholar → DBLP
- **score ≥ 0.85 的自动匹配**（子串命中等高置信场景）
- **score < 0.85 的返回候选列表**，标记为 `needs_review`
- 遵守 API 限流（arXiv 3s, Semantic Scholar 1s）
- 输出 `/tmp/paper-fetcher-tmp/search_results.json`

#### Step 3: 读取搜索结果，LLM 审阅候选

读取 `/tmp/paper-fetcher-tmp/search_results.json`，每篇论文的 status 有三种：

| status | 含义 | 处理方式 |
|--------|------|----------|
| `found` | 自动匹配成功（score≥0.85） | ✅ 直接使用 |
| `needs_review` | 有候选但不确定 | 🤔 **LLM 审阅候选列表，选出正确论文** |
| `not_found` | 所有 API 无结果 | ❌ Phase 4b WebSearch 兜底 |

对 `needs_review` 的论文，结果中包含 `candidates` 数组：
```json
{
  "id": 2,
  "original_title": "PREMem",
  "status": "needs_review",
  "candidates": [
    {"title": "Pre-Storage Reasoning for Episodic Memory: Shifting Inference to the Front", "source": "arxiv", "arxiv_id": "2501.12345", "pdf_url": "https://arxiv.org/pdf/2501.12345.pdf", "score": 0.0},
    {"title": "Predictive Memory Networks for Robot Navigation", "source": "semantic_scholar", "arxiv_id": "", "pdf_url": "", "score": 0.0}
  ]
}
```

**LLM 审阅规则：**
- 阅读候选列表的标题，用语义理解判断哪个是目标论文
- 如 "PREMem" 是 "**PRE**-storage reasoning for episodic **Mem**ory" 的缩写 → 选第一个
- 选定后，将该论文的 `matched_title`、`arxiv_id`、`pdf_url` 填入 result，`status` 改为 `found`
- 如果候选中没有正确论文 → `status` 保持 `not_found`，Phase 4b 兜底

### 搜索提示构建规则
`hints` 字段应包含尽可能多的辅助信息（空格分隔）：
- 作者名（如 "Vaswani"）
- 会议/期刊名（如 "NeurIPS 2017"）
- 用户描述中的关键词（**特别是对缩写论文名，把全称关键词放在 hints 中**）
- 已知的 arXiv ID

### 个别搜索脚本（仅用于手动调试或 WebSearch 兜底后的补充搜索）

| 脚本 | 平台 | 用法 |
|------|------|------|
| `search-arxiv.sh` | arXiv | `bash search-arxiv.sh "关键词" [数量]` |
| `search-semantic-scholar.sh` | Semantic Scholar | `bash search-semantic-scholar.sh "关键词" [数量]` |
| `search-dblp.sh` | DBLP | `bash search-dblp.sh "关键词" [数量]` |
| `search-github.sh` | GitHub | `bash search-github.sh "关键词" [数量]` |

---

## Phase 3: 批量下载 PDF

### 任务
使用 `batch-download.sh` 一次性下载所有已找到链接的论文。

### 操作步骤

```bash
bash ~/.claude/skills/paper-fetcher/scripts/batch-download.sh /tmp/paper-fetcher-tmp/search_results.json /tmp/paper-fetcher-tmp
```

脚本会自动：
- 读取搜索结果，只下载 `status=found` 且有 `pdf_url` 的论文
- 通过 `download-paper.sh` 下载每篇论文（内置重试 2 次）
- 验证下载文件的 PDF 格式（magic bytes）
- 按 `{序号}_{标题简写}.pdf` 命名
- 输出 `/tmp/paper-fetcher-tmp/download_results.json`

### 下载结果格式
```json
[
  {"id": 1, "filename": "01_Attention_Is_All_You_Need.pdf", "path": "/tmp/.../xxx.pdf", "status": "success", "size_kb": 1234},
  {"id": 2, "filename": "02_BERT.pdf", "path": "/tmp/.../xxx.pdf", "status": "failed", "error": "PDF 格式无效"}
]
```

### 重要约束
- **所有下载必须通过预定义脚本**：不要自行构造 curl 命令
- 所有文件先下载到 `/tmp/paper-fetcher-tmp/`，Phase 5 再移动到最终目录
- 脚本会自动处理 arXiv / OpenReview / 直接 URL 不同来源的下载逻辑

---

## Phase 4: 批量内容验证

下载的 PDF 可能是**错误的论文**（如搜索 NLP 论文却下载到同名的数学论文），因此必须验证内容。

**设计原则**：脚本负责文本提取与基础归一化，语义判断全部交给 LLM。
- PDF 文本提取常带有 LaTeX 伪影（如 "N EMORI" 实为 "NEMORI"），纯规则难以覆盖
- 主题相关性判断需要语义理解能力，简单关键词匹配容易误判

### Step 1: 文本提取

```bash
bash ~/.claude/skills/paper-fetcher/scripts/batch-verify.sh /tmp/paper-fetcher-tmp/download_results.json /tmp/paper-fetcher-tmp/papers.json
```

脚本会自动：
- 提取每个 PDF 前 3 页文本（pdftotext → PyPDF2 → strings 三级回退）
- 修复 LaTeX 伪影（Unicode 归一化、spaced-letter 合并）
- 提取结构化字段：`extracted_title`、`abstract`、`intro_snippet`
- 仅对归一化后标题精确子串命中的论文自动确认（`auto_correct`）
- 其余全部标记 `needs_review` 交给 LLM
- 输出 `/tmp/paper-fetcher-tmp/verify_extracts.json`

### 提取结果格式
```json
[
  {
    "id": 1,
    "expected_title": "Attention Is All You Need",
    "extracted_title": "Attention Is All You Need",
    "abstract": "The dominant sequence transduction models...",
    "intro_snippet": "Recurrent neural networks, long short-term memory...",
    "auto_verdict": "auto_correct|needs_review|no_text|file_missing"
  }
]
```

### Step 2: LLM 语义审阅

读取 `verify_extracts.json`，对每篇 `auto_verdict == "needs_review"` 的论文：

**LLM 审阅依据：**
- `expected_title` vs `extracted_title` — 标题是否匹配（考虑缩写、副标题、LaTeX 伪影）
- `abstract` — 论文摘要内容是否与期望主题相关
- `intro_snippet` — 引言是否在讨论相关问题

**LLM 判定输出（更新到结果中）：**

| verdict | 含义 | 处理 |
|---------|------|------|
| `correct` | 标题匹配 + 主题相关 | ✅ 保留，移动到最终目录 |
| `wrong_paper` | 不是目标论文 | ❌ 删除，Phase 4b WebSearch 补救 |
| `off_topic` | 标题匹配但主题不相关 | ⚠️ 保留，README 中标注 |
| `no_text` | 无法提取文本 | ⚠️ 保留，无法判断 |

对 `auto_correct` 的论文直接视为 `correct`，无需二次审阅。

### Phase 4b: WebSearch 补救（仅针对失败项）

读取验证结果后，对以下情况用 WebSearch 补救：

1. **Phase 2 搜索 not_found 的论文**：
   ```
   WebSearch: "{论文标题}" arxiv OR openreview pdf
   ```
   - 找到链接后，用 `download-paper.sh` 单独下载

2. **LLM 判定 wrong_paper 的论文**：
   - 删除错误文件
   - 用更精确的关键词 WebSearch（加上作者、年份、会议名）
   - 找到后单独下载并验证

### 补救搜索技巧
- 论文名称很短/很通用 → 加上年份和作者名
- 如 "A-MEM" 找不到 → 搜 "A-MEM agent memory Zettelkasten 2025"
- 利用用户描述中的关键词补充搜索

---

## Phase 5: 整理分类 & 生成报告

### 输出目录结构

#### 有分类信息时
```
~/Desktop/{topic}/
├── README.md
├── {Category1}/
│   ├── 01_{Paper_Title}.pdf
│   ├── 02_{Paper_Title}.pdf
│   └── ...
├── {Category2}/
│   └── 01_{Paper_Title}.pdf
└── uncategorized/
    └── 01_{Paper_Title}.pdf
```

#### 无分类信息时
```
~/Desktop/{topic}/
├── README.md
├── 01_{Paper_Title}.pdf
├── 02_{Paper_Title}.pdf
└── ...
```

### 文件命名规则
- 格式：`{两位序号}_{英文标题简写}.pdf`
- 标题简写：取论文标题前几个关键词，用下划线连接，不超过 80 字符
- 移除标题中的特殊字符：`/ \ : * ? " < > |`
- 序号在每个分类文件夹内独立编号，从 01 开始

### 去重规则
- 同一论文（标题相似度高）只保留一个
- arXiv 论文保留最新版本（最大版本号）
- 优先保留 arXiv 来源 > OpenReview > 其他

### README.md 模板

在顶层目录生成 README.md，内容包括：

```markdown
# {topic} - 论文下载报告

> 生成时间: {timestamp}
> 论文总数: {total} 篇
> 成功下载: {success} 篇
> 下载失败: {failed} 篇

## 下载统计

| 序号 | 论文标题 | 来源 | 状态 | 分类 |
|------|----------|------|------|------|
| 1 | Attention Is All You Need | arXiv:1706.03762 | ✅ 成功 | Transformer |
| 2 | Some Paper | - | ❌ 未找到 | - |

## 分类概览
- **{Category1}**: {count} 篇
- **{Category2}**: {count} 篇

## 失败列表
以下论文未能成功下载：
1. {论文标题} - 原因: {未找到/下载失败/文件无效}
```

---

## 错误处理

| 场景 | 处理方式 |
|------|----------|
| 搜索无结果 | 在 README 中标记为"未找到"，继续处理其他论文 |
| 下载失败 | 脚本内置重试，仍失败则标记在 README 中 |
| PDF 格式无效 | 删除文件，标记为"文件无效" |
| 下载到错误论文 | 删除文件，用更精确的关键词重新搜索 1 次 |
| 论文与主题不相关 | 保留文件，在 README 中标注"可能不相关" |
| API 限流 | 等待 5 秒后重试，或切换到备用搜索策略 |
| 网络超时 | 重试 1 次，超时时间设为 60 秒 |

---

## 重要约束

1. **仅使用合法开源来源**：arXiv、OpenReview 等公开平台
2. **不要编造链接**：只使用搜索到的真实链接，通过脚本下载
3. **不要猜测 arXiv ID**：必须通过搜索确认
4. **尊重 API 限流**：arXiv API 建议间隔 3 秒，下载间隔 1 秒
5. **所有下载必须通过预定义脚本**：不要自行构造 curl 命令
6. **每篇下载的论文都必须经过内容验证**：不能只检查文件格式，必须读取 PDF 内容确认标题和主题匹配

---

## Bash 调用次数汇总

核心流程通过 3 次批量脚本调用完成，辅以少量文件整理操作：

| 阶段 | Bash 调用 | 说明 |
|------|-----------|------|
| Phase 1 | 0 次 | LLM 直接识别，Write 写 JSON 文件 |
| Phase 2 | 1 次 | `batch-search.sh` 批量搜索 + LLM 审阅低置信度候选 |
| Phase 3 | 1 次 | `batch-download.sh` 批量下载 |
| Phase 4 | 1 次 | `batch-verify.sh` 文本提取 + LLM 语义审阅 |
| Phase 4b | 0~3 次 | WebSearch 补救 + 个别 `download-paper.sh` 单独下载 |
| Phase 5 | 1~2 次 | mkdir + mv/cp 整理到 Desktop |

**典型场景总计 4~6 次 Bash 调用，与论文数量无关。**
