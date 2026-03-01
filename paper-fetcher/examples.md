# Paper Fetcher 使用示例

## 示例 1: 带分类的论文列表

输入：
```
帮我下载以下论文：

Memory Mechanisms & Algorithms（记忆机制与算法）
- A-MEM [2025/02]：借鉴 Zettelkasten 笔记法，构建了一个能动态链接、持续演化的智能体驱动记忆网络
- AgentFold [2025/10]：自动压缩工作记忆，在多步交互中进行上下文折叠
- AlphaEdit [2024/10]：基于规则或模型的参数编辑器

Memory-Augmented Architectures（记忆增强架构）
- Atkinson-Shiffrin Model (XMem) [2022/07]：视频对象分割模型借鉴经典三级记忆模型
- Compress to Impress [2025]：长对话中的压缩式记忆机制
```

预期输出目录：
```
~/Desktop/Memory_Mechanisms/
├── README.md
├── Memory_Mechanisms_and_Algorithms/
│   ├── 01_A-MEM.pdf
│   ├── 02_AgentFold.pdf
│   └── 03_AlphaEdit.pdf
└── Memory_Augmented_Architectures/
    ├── 01_XMem_Atkinson_Shiffrin.pdf
    └── 02_Compress_to_Impress.pdf
```

---

## 示例 2: 简单论文列表（无分类）

输入：
```
下载这些论文：
Attention Is All You Need
BERT: Pre-training of Deep Bidirectional Transformers
GPT-4 Technical Report
```

预期输出目录：
```
~/Desktop/Transformer_Models/
├── README.md
├── 01_Attention_Is_All_You_Need.pdf
├── 02_BERT_Pre_training.pdf
└── 03_GPT4_Technical_Report.pdf
```

---

## 示例 3: 从自然语言描述提取

输入：
```
我在读一篇 survey，里面提到了 ReAct 这篇 prompting 的论文，
还有 Chain-of-Thought Prompting 和 Tree of Thoughts，帮我都下载了
```

预期行为：
1. 识别出 3 篇论文：ReAct, Chain-of-Thought Prompting, Tree of Thoughts
2. 无分类信息 → 全部放同一目录
3. 推断主题为 "LLM Prompting"

---

## 示例 4: README 报告示例

```markdown
# LLM_Memory - 论文下载报告

> 生成时间: 2026-03-01 14:30:00
> 论文总数: 9 篇
> 成功下载: 7 篇
> 下载失败: 2 篇

## 下载统计

| 序号 | 论文标题 | 来源 | 状态 | 分类 |
|------|----------|------|------|------|
| 1 | A-MEM | arXiv:2502.12345 | ✅ 成功 | Memory Mechanisms |
| 2 | AgentFold | arXiv:2510.54321 | ✅ 成功 | Memory Mechanisms |
| 3 | AlphaEdit | arXiv:2410.11111 | ✅ 成功 | Memory Mechanisms |
| 4 | XMem | arXiv:2207.22222 | ✅ 成功 | Architectures |
| 5 | Unknown Paper | - | ❌ 未找到 | - |

## 分类概览
- **Memory Mechanisms**: 3 篇
- **Architectures**: 4 篇

## 失败列表
以下论文未能成功下载：
1. Unknown Paper - 原因: arXiv 和 WebSearch 均未找到匹配结果
2. Another Paper - 原因: 下载超时
```
