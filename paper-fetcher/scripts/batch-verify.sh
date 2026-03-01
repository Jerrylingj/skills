#!/bin/bash
# 批量 PDF 文本提取脚本（一次调用处理所有已下载的 PDF）
# 用法: bash batch-verify.sh <download_results_json> <papers_json>
#
# 设计原则：
#   脚本只做机械工作：从 PDF 提取结构化文本片段
#   语义判断（标题是否匹配、主题是否相关）全部交给 LLM/SubAgent
#
# 输出: verify_extracts.json，每篇论文包含:
#   - extracted_title: 从 PDF 提取的疑似标题
#   - abstract: 摘要文本
#   - intro_snippet: 引言前 300 字符
#   - auto_verdict: 仅对极高置信度自动判定
#     "auto_correct" = 归一化后标题精确命中
#     "needs_review" = 需要 LLM 审阅
#     "no_text" / "file_missing" = 异常情况
#
# 一次 bash 调用完成所有提取，无需逐篇审批

DOWNLOAD_RESULTS="${1:-}"
PAPERS_JSON="${2:-}"

if [ -z "$DOWNLOAD_RESULTS" ] || [ -z "$PAPERS_JSON" ]; then
    echo "用法: $0 <download_results_json> <papers_json>"
    echo "示例: $0 /tmp/paper-fetcher-tmp/download_results.json /tmp/paper-fetcher-tmp/papers.json"
    exit 1
fi

# 导出变量供 Python heredoc 使用
export DOWNLOAD_RESULTS
export PAPERS_JSON

python3 << 'PYTHON_SCRIPT'
import json
import os
import re
import subprocess
import unicodedata

DOWNLOAD_RESULTS = os.environ.get("DOWNLOAD_RESULTS", "")
PAPERS_JSON = os.environ.get("PAPERS_JSON", "")

with open(DOWNLOAD_RESULTS, 'r') as f:
    downloads = json.load(f)

with open(PAPERS_JSON, 'r') as f:
    papers = json.load(f)

paper_map = {p['id']: p for p in papers}
successful = [d for d in downloads if d.get('status') == 'success']

print(f"🔍 开始提取 {len(successful)} 篇 PDF 的结构化文本...")
print()

# ===== 文本提取工具 =====

def extract_text(filepath, max_pages=3):
    """从 PDF 提取文本，多种方法回退"""
    for method in ['pdftotext', 'pypdf2', 'strings']:
        if method == 'pdftotext':
            try:
                r = subprocess.run(
                    ['pdftotext', '-f', '1', '-l', str(max_pages), '-layout', filepath, '-'],
                    capture_output=True, text=True, timeout=30)
                if r.returncode == 0 and len(r.stdout.strip()) > 100:
                    return r.stdout
            except (FileNotFoundError, subprocess.TimeoutExpired):
                pass
        elif method == 'pypdf2':
            try:
                from PyPDF2 import PdfReader
                reader = PdfReader(filepath)
                text = ""
                for i in range(min(max_pages, len(reader.pages))):
                    t = reader.pages[i].extract_text()
                    if t: text += t + "\n"
                if len(text.strip()) > 100:
                    return text
            except Exception:
                pass
        elif method == 'strings':
            try:
                r = subprocess.run(['strings', filepath],
                    capture_output=True, text=True, timeout=15)
                if r.returncode == 0:
                    return '\n'.join(r.stdout.split('\n')[:300])
            except Exception:
                pass
    return ""

def normalize_latex(text):
    """修复 pdftotext 的 LaTeX 伪影
    "N EMORI" → "NEMORI", "G ÖDEL" → "GODEL"
    """
    text = unicodedata.normalize('NFKD', text)
    text = ''.join(c for c in text if not unicodedata.combining(c))
    
    def fix_spaced(line):
        return re.sub(r'(?<![a-zA-Z])([A-Z] ){2,}[A-Z](?![a-zA-Z])',
                       lambda m: m.group(0).replace(' ', ''), line)
    return '\n'.join(fix_spaced(l) for l in text.split('\n'))

# ===== 结构化信息提取 =====

def extract_title(text):
    """猜测论文标题（文本前 25 行中第一个合适长度的行）"""
    for line in [l.strip() for l in text.split('\n') if l.strip()][:25]:
        if re.match(r'^(page\s+\d|http|www\.|©|\d{4}[/-]|arxiv:|preprint)', line, re.I):
            continue
        if '@' in line and '.' in line:
            continue
        if re.match(r'^\d+$', line.strip()):
            continue
        if 10 < len(line) < 300:
            return line
    return ""

def extract_abstract(text):
    """提取摘要（Abstract 到下一个 section 之间的文本）"""
    # 尝试匹配 "Abstract" 标记
    m = re.search(r'(?:^|\n)\s*(?:Abstract|ABSTRACT)[:\s.\-—]*\n?(.*?)(?:\n\s*(?:\d+[\.\s]|I+[\.\s]|Introduction|INTRODUCTION|Keywords|1\s))', 
                  text[:5000], re.S | re.I)
    if m and len(m.group(1).strip()) > 30:
        return m.group(1).strip()[:600]
    
    # 宽松匹配
    m = re.search(r'(?:abstract|ABSTRACT)[:\s.\-—]*(.{30,800}?)(?:\n\s*\n|\n\s*(?:Introduction|INTRODUCTION|Keywords|1[\.\s]))',
                  text[:5000], re.S | re.I)
    if m:
        return m.group(1).strip()[:600]
    
    return ""

def extract_intro(text):
    """提取引言前 300 字符"""
    m = re.search(r'(?:^|\n)\s*(?:1[\.\s]*)?(?:Introduction|INTRODUCTION)[:\s]*\n?(.*)',
                  text[:8000], re.S | re.I)
    if m:
        intro = m.group(1).strip()[:400]
        # 截断到最后一个完整句子
        last_period = intro.rfind('.')
        if last_period > 100:
            intro = intro[:last_period+1]
        return intro
    return ""

def auto_title_match(expected, extracted_title, full_text):
    """极高置信度自动匹配（归一化后子串命中）
    
    只有非常确定才返回 True，稍有不确定就返回 False 交给 LLM
    """
    def norm(s):
        s = unicodedata.normalize('NFKD', s)
        s = ''.join(c for c in s if not unicodedata.combining(c))
        return re.sub(r'[^a-z0-9]', '', s.lower())
    
    exp = norm(expected)
    if not exp or len(exp) < 2:
        return False
    
    # 归一化标题子串匹配
    if extracted_title:
        act = norm(extracted_title)
        if exp in act or act in exp:
            return True
    
    # 归一化后在文本前 2000 字符中找
    head = norm(full_text[:2000])
    if exp in head:
        return True
    
    # 短标题: 原文精确词匹配
    if len(expected.strip()) <= 12:
        if re.search(r'\b' + re.escape(expected.strip()) + r'\b', full_text[:2000], re.I):
            return True
    
    return False

# ===== 主循环 =====

extracts = []
auto_ok = 0
need_review = 0

for dl in successful:
    pid = dl['id']
    filepath = dl.get('path', '')
    expected = paper_map.get(pid, {}).get('title', '')
    
    rec = {
        'id': pid,
        'expected_title': expected,
        'extracted_title': '',
        'abstract': '',
        'intro_snippet': '',
        'auto_verdict': 'needs_review',
    }
    
    if not os.path.exists(filepath):
        rec['auto_verdict'] = 'file_missing'
        print(f"  [{pid}] {expected[:40]}... → ❌ 文件不存在")
        extracts.append(rec)
        continue
    
    raw = extract_text(filepath)
    if len(raw.strip()) < 50:
        rec['auto_verdict'] = 'no_text'
        print(f"  [{pid}] {expected[:40]}... → ⚠️ 无法提取文本")
        extracts.append(rec)
        continue
    
    text = normalize_latex(raw)
    
    rec['extracted_title'] = extract_title(text)
    rec['abstract'] = extract_abstract(text)
    rec['intro_snippet'] = extract_intro(text)
    
    if auto_title_match(expected, rec['extracted_title'], text):
        rec['auto_verdict'] = 'auto_correct'
        auto_ok += 1
        print(f"  [{pid}] {expected[:40]}... → ✅ 自动确认")
    else:
        rec['auto_verdict'] = 'needs_review'
        need_review += 1
        print(f"  [{pid}] {expected[:40]}... → 🤔 待审阅 (提取: \"{rec['extracted_title'][:50]}\")")
    
    extracts.append(rec)

# ===== 输出 =====
output_dir = os.path.dirname(DOWNLOAD_RESULTS)
out_file = os.path.join(output_dir, 'verify_extracts.json')
with open(out_file, 'w') as f:
    json.dump(extracts, f, ensure_ascii=False, indent=2)

no_text = sum(1 for r in extracts if r['auto_verdict'] == 'no_text')
missing = sum(1 for r in extracts if r['auto_verdict'] == 'file_missing')

print()
print(f"{'='*50}")
print(f"📊 文本提取完成:")
print(f"   ✅ 自动确认: {auto_ok} 篇")
print(f"   🤔 待LLM审阅: {need_review} 篇")
if no_text: print(f"   ⚠️ 无文本: {no_text} 篇")
if missing: print(f"   ❌ 文件缺失: {missing} 篇")
print(f"📄 提取结果: {out_file}")

if need_review > 0:
    print()
    print("🤔 以下论文需要 LLM/SubAgent 审阅:")
    for r in extracts:
        if r['auto_verdict'] == 'needs_review':
            print(f"   [{r['id']}] 期望: \"{r['expected_title']}\"")
            print(f"        提取: \"{r['extracted_title'][:60]}\"")
PYTHON_SCRIPT
