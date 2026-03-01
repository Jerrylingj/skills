#!/bin/bash
# 批量论文搜索脚本（一次调用搜索所有论文）
# 用法: bash batch-search.sh <papers_json_file> [output_json_file]
#
# 输入: JSON 文件，格式为:
# [
#   {"id": 1, "title": "Attention Is All You Need", "year": "2017", "hints": "Vaswani, Transformer"},
#   {"id": 2, "title": "BERT", "year": "2019", "hints": ""}
# ]
#
# 输出: JSON 文件，每篇论文的搜索结果
# 搜索策略: arXiv API → Semantic Scholar → DBLP（自动回退）
#
# 一次 bash 调用完成所有搜索，无需逐篇审批

PAPERS_FILE="${1:-}"
OUTPUT_FILE="${2:-/tmp/paper-fetcher-tmp/search_results.json}"

if [ -z "$PAPERS_FILE" ]; then
    echo "用法: $0 <papers_json_file> [output_json_file]"
    echo ""
    echo "示例:"
    echo '  echo '\''[{"id":1,"title":"Attention Is All You Need","year":"2017","hints":""}]'\'' > /tmp/papers.json'
    echo "  $0 /tmp/papers.json"
    exit 1
fi

if [ ! -f "$PAPERS_FILE" ]; then
    echo "ERROR: 文件不存在: $PAPERS_FILE"
    exit 1
fi

mkdir -p "$(dirname "$OUTPUT_FILE")"

# 导出变量供 Python heredoc 使用
export PAPERS_FILE
export OUTPUT_FILE

# 使用 Python3 执行批量搜索（一个进程搞定所有）
python3 << 'PYTHON_SCRIPT'
import json
import sys
import urllib.request
import urllib.parse
import xml.etree.ElementTree as ET
import time
import os
import re

PAPERS_FILE = os.environ.get("PAPERS_FILE", "")
OUTPUT_FILE = os.environ.get("OUTPUT_FILE", "")

# ===== 读取输入 =====
with open(PAPERS_FILE, 'r') as f:
    papers = json.load(f)

print(f"📋 开始搜索 {len(papers)} 篇论文...")
print()

results = []

def safe_request(url, timeout=20):
    """安全的 HTTP 请求，带错误处理"""
    try:
        req = urllib.request.Request(url, headers={
            'User-Agent': 'Mozilla/5.0 PaperFetcher/1.0'
        })
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.read().decode('utf-8')
    except Exception as e:
        return None

# ===== 搜索函数 =====

# arXiv API 的停用词（不参与搜索）
STOP_WORDS = {'the', 'a', 'an', 'of', 'in', 'for', 'and', 'or', 'to', 'with', 'on', 'at', 'by', 'from', 'is', 'are', 'was', 'were', 'its', 'it'}

def build_arxiv_query(title, field='ti'):
    """构建 arXiv API 查询字符串
    
    arXiv API 语法: ti:word 只对第一个词生效，
    多词必须用 AND 连接: ti:word1+AND+ti:word2
    短标题用精确短语: ti:\"AlphaEdit\"
    """
    # 清理标题
    clean = re.sub(r'[^\w\s-]', ' ', title)  # 保留连字符
    words = clean.split()
    
    # 过滤停用词（但如果全是停用词则保留）
    key_words = [w for w in words if w.lower() not in STOP_WORDS]
    if not key_words:
        key_words = words
    
    if len(key_words) == 0:
        return None
    
    if len(key_words) == 1:
        # 单词查询
        return f'{field}:{urllib.parse.quote(key_words[0])}'
    elif len(key_words) <= 3:
        # 短查询: 用精确短语 + AND 连接两种策略
        # 策略 1: AND 连接
        parts = [f'{field}:{urllib.parse.quote(w)}' for w in key_words]
        return '+AND+'.join(parts)
    else:
        # 长查询: 取最关键的几个词 AND 连接（最多 5 个）
        # 跳过太短的词（< 3字符）
        important = [w for w in key_words if len(w) >= 3][:5]
        if not important:
            important = key_words[:5]
        parts = [f'{field}:{urllib.parse.quote(w)}' for w in important]
        return '+AND+'.join(parts)

def search_arxiv(title, max_results=5):
    """通过 arXiv API 搜索"""
    
    # 先搜标题字段，再搜全部
    for field in ['ti', 'all']:
        query = build_arxiv_query(title, field)
        if not query:
            continue
        url = f"https://export.arxiv.org/api/query?search_query={query}&max_results={max_results}&sortBy=relevance"
        response = safe_request(url)
        if not response:
            continue
        
        try:
            # 解析 XML
            root = ET.fromstring(response)
            ns = {'atom': 'http://www.w3.org/2005/Atom'}
            entries = root.findall('atom:entry', ns)
            
            if not entries:
                continue
            
            matches = []
            for entry in entries:
                entry_title = entry.find('atom:title', ns)
                entry_id = entry.find('atom:id', ns)
                entry_published = entry.find('atom:published', ns)
                entry_updated = entry.find('atom:updated', ns)
                entry_summary = entry.find('atom:summary', ns)
                
                if entry_title is not None and entry_id is not None:
                    arxiv_url = entry_id.text.strip()
                    arxiv_id = arxiv_url.replace('http://arxiv.org/abs/', '').replace('https://arxiv.org/abs/', '')
                    base_id = re.sub(r'v\d+$', '', arxiv_id)
                    
                    matches.append({
                        'title': ' '.join(entry_title.text.strip().split()),
                        'arxiv_id': base_id,
                        'pdf_url': f'https://arxiv.org/pdf/{base_id}.pdf',
                        'published': entry_published.text.strip() if entry_published is not None else '',
                        'updated': entry_updated.text.strip() if entry_updated is not None else '',
                        'summary': ' '.join(entry_summary.text.strip().split())[:200] if entry_summary is not None else '',
                    })
            
            if matches:
                return matches
        except ET.ParseError:
            continue
    
    return []

def search_semantic_scholar(title, max_results=5):
    """通过 Semantic Scholar API 搜索"""
    encoded = urllib.parse.quote(title)
    fields = "paperId,title,authors,year,externalIds,openAccessPdf,url"
    url = f"https://api.semanticscholar.org/graph/v1/paper/search?query={encoded}&limit={max_results}&fields={fields}"
    
    response = safe_request(url)
    if not response:
        return []
    
    try:
        data = json.loads(response)
        papers_data = data.get('data', [])
        
        matches = []
        for paper in papers_data:
            ext_ids = paper.get('externalIds', {}) or {}
            arxiv_id = ext_ids.get('ArXiv', '')
            doi = ext_ids.get('DOI', '')
            
            oa_pdf = paper.get('openAccessPdf', {}) or {}
            pdf_url = oa_pdf.get('url', '')
            if not pdf_url and arxiv_id:
                pdf_url = f'https://arxiv.org/pdf/{arxiv_id}.pdf'
            
            authors = paper.get('authors', []) or []
            author_str = ', '.join([a.get('name', '') for a in authors[:3]])
            
            matches.append({
                'title': paper.get('title', ''),
                'arxiv_id': arxiv_id,
                'doi': doi,
                'pdf_url': pdf_url,
                'year': paper.get('year', ''),
                'authors': author_str,
            })
        
        return matches
    except (json.JSONDecodeError, KeyError):
        return []

def search_dblp(title, max_results=5):
    """通过 DBLP API 搜索"""
    encoded = urllib.parse.quote(title)
    url = f"https://dblp.org/search/publ/api?q={encoded}&h={max_results}&format=json"
    
    response = safe_request(url)
    if not response:
        return []
    
    try:
        data = json.loads(response)
        hits = data.get('result', {}).get('hits', {}).get('hit', [])
        if isinstance(hits, dict):
            hits = [hits]
        
        matches = []
        for hit in hits:
            info = hit.get('info', {})
            t = info.get('title', '')
            if t.endswith('.'):
                t = t[:-1]
            
            ee = info.get('ee', '')
            doi = info.get('doi', '')
            
            # 尝试从 ee URL 中提取 arXiv ID
            arxiv_id = ''
            if isinstance(ee, str) and 'arxiv.org' in ee:
                m = re.search(r'(\d{4}\.\d{4,5})', ee)
                if m:
                    arxiv_id = m.group(1)
            
            pdf_url = ''
            if arxiv_id:
                pdf_url = f'https://arxiv.org/pdf/{arxiv_id}.pdf'
            elif isinstance(ee, str) and ee.endswith('.pdf'):
                pdf_url = ee
            
            matches.append({
                'title': t,
                'arxiv_id': arxiv_id,
                'doi': doi if isinstance(doi, str) else '',
                'pdf_url': pdf_url,
                'year': info.get('year', ''),
                'venue': info.get('venue', ''),
                'ee_url': ee if isinstance(ee, str) else '',
            })
        
        return matches
    except (json.JSONDecodeError, KeyError):
        return []

def acronym_match(query, candidate_title):
    """检查 query 是否是 candidate_title 各词前缀的拼接（缩写匹配）
    
    PREMem → Pre-storage ... Episodic Memory (PRE + Mem)
    SCM → Structured Context Memory
    MemOS → Memory Operating System
    """
    q = query.lower()
    # 将 candidate 拆成单词（连字符也拆开），去停用词
    words = [w.lower() for w in re.split(r'[\s\-:,]+', candidate_title) 
             if w and w.lower() not in STOP_WORDS]
    
    if not words or len(q) < 2:
        return False
    
    # 贪心+回溯：尝试将 query 的字符依次匹配为 candidate 各词的前缀
    def greedy_match(qi, wi, matched_words):
        if qi == len(q):
            return matched_words >= 2  # 至少匹配到 2 个词的前缀
        if wi >= len(words):
            return False
        
        word = words[wi]
        # 尝试匹配当前词的前缀（至少 1 个字符）
        prefix_len = 0
        while qi + prefix_len < len(q) and prefix_len < len(word) and q[qi + prefix_len] == word[prefix_len]:
            prefix_len += 1
        
        # 匹配到了前缀 → 消耗 query 字符，跳到下一个词
        if prefix_len >= 1:
            if greedy_match(qi + prefix_len, wi + 1, matched_words + 1):
                return True
        
        # 跳过当前词（不匹配这个词）
        return greedy_match(qi, wi + 1, matched_words)
    
    return greedy_match(0, 0, 0)

def title_similarity(query, candidate):
    """智能标题匹配（非对称：query 是否匹配 candidate）
    
    解决核心问题：用户查询 "AlphaEdit" 必须能匹配
    "AlphaEdit: Null-Space Constrained Knowledge Editing for Language Models"
    
    返回 0~1 的匹配分数
    """
    q = query.strip()
    c = candidate.strip()
    q_lower = q.lower()
    c_lower = c.lower()
    
    if not q or not c:
        return 0.0
    
    # === 策略 1: 精确匹配 ===
    if q_lower == c_lower:
        return 1.0
    
    # === 策略 2: 子串包含 ===
    # "AlphaEdit" in "AlphaEdit: Null-Space Constrained..." → 0.9
    if q_lower in c_lower:
        return 0.9
    
    # === 策略 3: 带连字符的子串 ===
    # "A-MEM" → 检查 "a-mem" 或 "amem" 是否在 candidate 中
    q_nohyphen = q_lower.replace('-', '')
    c_nohyphen = c_lower.replace('-', '')
    if q_nohyphen in c_nohyphen:
        return 0.85
    
    # === 策略 4: 词级别匹配 ===
    def tokenize(t):
        # 保留连字符（如 A-MEM），其他标点变空格
        return [w for w in re.sub(r'[^\w\s-]', ' ', t.lower()).split() if w]
    
    q_words = tokenize(q)
    c_words = tokenize(c)
    q_words_set = set(q_words)
    c_words_set = set(c_words)
    
    if not q_words or not c_words:
        return 0.0
    
    # 非对称包含度：query 的词有多少出现在 candidate 中？
    # （包括子串匹配："mem" 能匹配 "memory"）
    matched = 0
    for qw in q_words:
        if qw in STOP_WORDS and len(q_words) > 2:
            matched += 0.5  # 停用词给半分
            continue
        # 精确词匹配
        if qw in c_words_set:
            matched += 1
            continue
        # 子串匹配: qw 是否是某个 candidate 词的子串，或反之
        # 要求子串长度 >= 3，避免 "a" 匹配 "a-mem" 的误报
        if any((qw in cw and len(qw) >= 3) or (cw in qw and len(cw) >= 3) for cw in c_words):
            matched += 0.8
            continue
    
    containment = matched / len(q_words)
    
    # 传统 Jaccard 作为补充
    intersection = q_words_set & c_words_set
    union = q_words_set | c_words_set
    jaccard = len(intersection) / len(union) if union else 0
    
    score = max(containment * 0.85, jaccard)
    
    # === 策略 5: 缩写拆解匹配 ===
    # PREMem → Pre-storage ... Episodic Memory
    # 仅当前面所有策略都没给出高分时才尝试（避免多余计算）
    if score < 0.4 and len(q_words) <= 2:
        if acronym_match(q, c):
            score = max(score, 0.80)
    
    return score

def find_best_match(target_title, candidates, threshold=0.3):
    """从候选列表中找最佳匹配
    
    对短标题(≤2词)自动降低阈值到 0.15
    """
    # 短标题自适应阈值
    word_count = len(target_title.split())
    effective_threshold = 0.15 if word_count <= 2 else threshold
    
    best = None
    best_score = 0
    
    for c in candidates:
        score = title_similarity(target_title, c.get('title', ''))
        if score > best_score:
            best_score = score
            best = c
    
    if best and best_score >= effective_threshold:
        return best, best_score
    return None, 0

# ===== 批量搜索主循环 =====

# 自动匹配阈值：高于此分数直接认定为匹配成功
AUTO_MATCH_THRESHOLD = 0.85

for paper in papers:
    pid = paper.get('id', '?')
    title = paper.get('title', '')
    year = paper.get('year', '')
    hints = paper.get('hints', '')
    
    # 构建搜索词
    search_term = title
    if hints:
        search_term_with_hints = f"{title} {hints}"
    else:
        search_term_with_hints = title
    
    print(f"🔍 [{pid}] 搜索: {title}")
    
    result = {
        'id': pid,
        'original_title': title,
        'matched_title': '',
        'source': '',
        'arxiv_id': '',
        'doi': '',
        'pdf_url': '',
        'status': 'not_found',
        'search_notes': '',
        'candidates': [],  # 候选列表，供 LLM 审阅
    }
    
    # 收集所有 API 返回的候选
    all_candidates = []
    found_auto = False
    
    # === 策略 1: arXiv ===
    print(f"   → arXiv API...", end=" ", flush=True)
    arxiv_results = search_arxiv(search_term)
    if arxiv_results:
        for ar in arxiv_results:
            score = title_similarity(title, ar.get('title', ''))
            all_candidates.append({
                'title': ar['title'],
                'source': 'arxiv',
                'arxiv_id': ar.get('arxiv_id', ''),
                'pdf_url': ar.get('pdf_url', ''),
                'score': round(score, 3),
            })
        best = max(all_candidates, key=lambda x: x['score'])
        if best['score'] >= AUTO_MATCH_THRESHOLD:
            result.update({
                'matched_title': best['title'],
                'source': best['source'],
                'arxiv_id': best['arxiv_id'],
                'pdf_url': best['pdf_url'],
                'status': 'found',
                'search_notes': f'arXiv自动匹配(score={best["score"]})',
            })
            print(f"✅ 自动匹配: {best['arxiv_id']} (score={best['score']})")
            found_auto = True
        else:
            print(f"待审阅 (最佳score={best['score']}, \"{best['title'][:50]}\")")
    else:
        print("无结果")
    time.sleep(3)
    
    if found_auto:
        result['candidates'] = all_candidates
        results.append(result)
        continue
    
    # === 策略 2: Semantic Scholar ===
    print(f"   → Semantic Scholar...", end=" ", flush=True)
    s2_results = search_semantic_scholar(search_term)
    if s2_results:
        for sr in s2_results:
            score = title_similarity(title, sr.get('title', ''))
            cand = {
                'title': sr.get('title', ''),
                'source': 'semantic_scholar',
                'arxiv_id': sr.get('arxiv_id', ''),
                'pdf_url': sr.get('pdf_url', ''),
                'score': round(score, 3),
            }
            all_candidates.append(cand)
            if score >= AUTO_MATCH_THRESHOLD and cand['pdf_url']:
                result.update({
                    'matched_title': cand['title'],
                    'source': 'semantic_scholar',
                    'arxiv_id': cand['arxiv_id'],
                    'doi': sr.get('doi', ''),
                    'pdf_url': cand['pdf_url'],
                    'status': 'found',
                    'search_notes': f'S2自动匹配(score={score:.2f})',
                })
                print(f"✅ 自动匹配: {cand['pdf_url'][:50]} (score={score:.2f})")
                found_auto = True
                break
        if not found_auto:
            best = max(all_candidates, key=lambda x: x['score']) if all_candidates else None
            if best:
                print(f"待审阅 (最佳score={best['score']})")
            else:
                print("无结果")
    else:
        print("无结果")
    time.sleep(1)
    
    if found_auto:
        result['candidates'] = all_candidates
        results.append(result)
        continue
    
    # === 策略 3: DBLP ===
    print(f"   → DBLP...", end=" ", flush=True)
    dblp_results = search_dblp(search_term)
    if dblp_results:
        for dr in dblp_results:
            score = title_similarity(title, dr.get('title', ''))
            cand = {
                'title': dr.get('title', ''),
                'source': 'dblp',
                'arxiv_id': dr.get('arxiv_id', ''),
                'pdf_url': dr.get('pdf_url', ''),
                'doi': dr.get('doi', ''),
                'ee_url': dr.get('ee_url', ''),
                'score': round(score, 3),
            }
            all_candidates.append(cand)
            if score >= AUTO_MATCH_THRESHOLD and cand.get('pdf_url'):
                result.update({
                    'matched_title': cand['title'],
                    'source': 'dblp',
                    'arxiv_id': cand['arxiv_id'],
                    'doi': cand.get('doi', ''),
                    'pdf_url': cand['pdf_url'],
                    'status': 'found',
                    'search_notes': f'DBLP自动匹配(score={score:.2f})',
                })
                print(f"✅ 自动匹配: {cand['pdf_url'][:50]} (score={score:.2f})")
                found_auto = True
                break
        if not found_auto:
            best = max(all_candidates, key=lambda x: x['score']) if all_candidates else None
            if best:
                print(f"待审阅 (最佳score={best['score']})")
            else:
                print("无结果")
    else:
        print("无结果")
    
    if found_auto:
        result['candidates'] = all_candidates
        results.append(result)
        continue
    
    # === 策略 4: 带 hints 重试 arXiv ===
    if hints and hints != title:
        print(f"   → arXiv (带提示词)...", end=" ", flush=True)
        time.sleep(3)
        arxiv_results = search_arxiv(search_term_with_hints, max_results=5)
        if arxiv_results:
            for ar in arxiv_results:
                score = title_similarity(title, ar.get('title', ''))
                cand = {
                    'title': ar['title'],
                    'source': 'arxiv',
                    'arxiv_id': ar.get('arxiv_id', ''),
                    'pdf_url': ar.get('pdf_url', ''),
                    'score': round(score, 3),
                }
                all_candidates.append(cand)
                if score >= AUTO_MATCH_THRESHOLD:
                    result.update({
                        'matched_title': cand['title'],
                        'source': 'arxiv',
                        'arxiv_id': cand['arxiv_id'],
                        'pdf_url': cand['pdf_url'],
                        'status': 'found',
                        'search_notes': f'arXiv(带提示)自动匹配(score={score:.2f})',
                    })
                    print(f"✅ 自动匹配: {cand['arxiv_id']} (score={score:.2f})")
                    found_auto = True
                    break
            if not found_auto:
                best = max(all_candidates, key=lambda x: x['score']) if all_candidates else None
                if best:
                    print(f"待审阅 (最佳score={best['score']})")
                else:
                    print("无结果")
        else:
            print("无结果")
    
    if found_auto:
        result['candidates'] = all_candidates
        results.append(result)
        continue
    
    # === 汇总: 有候选但未自动匹配 → 交给 LLM ===
    # 去重并按 score 排序
    seen = set()
    unique_candidates = []
    for c in sorted(all_candidates, key=lambda x: x['score'], reverse=True):
        key = c.get('arxiv_id') or c.get('title', '')
        if key not in seen:
            seen.add(key)
            unique_candidates.append(c)
    
    result['candidates'] = unique_candidates[:8]  # 最多保留 8 个候选
    
    if unique_candidates:
        result['status'] = 'needs_review'
        result['search_notes'] = f'有{len(unique_candidates)}个候选，需要 LLM 判断哪个是目标论文'
        print(f"   🤔 有 {len(unique_candidates)} 个候选待 LLM 审阅")
    else:
        result['status'] = 'not_found'
        result['search_notes'] = '所有自动搜索源均无结果，需要 WebSearch 兜底'
        print(f"   ❌ 未找到，标记为需要 WebSearch")
    
    results.append(result)

# ===== 输出结果 =====
with open(OUTPUT_FILE, 'w') as f:
    json.dump(results, f, ensure_ascii=False, indent=2)

# 统计
found = sum(1 for r in results if r['status'] == 'found')
needs_review = sum(1 for r in results if r['status'] == 'needs_review')
not_found = sum(1 for r in results if r['status'] == 'not_found')
partial = sum(1 for r in results if r['status'] == 'found_no_pdf')

print()
print(f"{'='*50}")
print(f"📊 搜索完成:")
print(f"   ✅ 自动匹配: {found} 篇")
print(f"   🤔 待LLM审阅: {needs_review} 篇")
print(f"   ❌ 未找到: {not_found} 篇")
if partial:
    print(f"   ⚠️ 无PDF链接: {partial} 篇")
print(f"📄 结果已保存: {OUTPUT_FILE}")

if needs_review > 0:
    print()
    print("🤔 以下论文需要 LLM 审阅候选列表:")
    for r in results:
        if r['status'] == 'needs_review':
            top = r['candidates'][0] if r['candidates'] else {}
            print(f"   - [{r['id']}] \"{r['original_title']}\" → 最佳候选: \"{top.get('title','?')[:50]}\" (score={top.get('score',0)})")

if not_found > 0:
    print()
    print("❌ 以下论文需要 WebSearch:")
    for r in results:
        if r['status'] == 'not_found':
            print(f"   - [{r['id']}] {r['original_title']}")
PYTHON_SCRIPT
