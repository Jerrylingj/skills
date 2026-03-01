#!/bin/bash
# Semantic Scholar 论文搜索脚本
# 用法: bash search-semantic-scholar.sh "论文标题关键词" [max_results]
#
# 通过 Semantic Scholar API 搜索论文
# 免费额度: 5000 次/5分钟（无需 API key）
# 输出: TITLE / PAPER_ID / ARXIV_ID / DOI / PDF_URL / YEAR / AUTHORS

QUERY="${1:-}"
MAX_RESULTS="${2:-5}"

if [ -z "$QUERY" ]; then
    echo "用法: $0 \"论文标题关键词\" [max_results]"
    echo "示例: $0 \"Attention Is All You Need\" 3"
    exit 1
fi

# URL 编码
urlencode() {
    echo -n "$1" | python3 -c "import sys, urllib.parse; print(urllib.parse.quote(sys.stdin.read()))" 2>/dev/null \
        || echo -n "$1" | sed 's/ /%20/g; s/"/%22/g; s/#/%23/g; s/&/%26/g; s/+/%2B/g; s/'\''/%27/g'
}

ENCODED_QUERY=$(urlencode "$QUERY")

FIELDS="paperId,title,authors,year,externalIds,openAccessPdf,url,citationCount"
API_URL="https://api.semanticscholar.org/graph/v1/paper/search?query=${ENCODED_QUERY}&limit=${MAX_RESULTS}&fields=${FIELDS}"

# 请求 API
RESPONSE=$(curl -L -s --max-time 30 \
    -H "Accept: application/json" \
    "$API_URL" 2>/dev/null)

CURL_EXIT=$?

if [ $CURL_EXIT -ne 0 ]; then
    echo "=== Semantic Scholar 搜索结果 ==="
    echo "ERROR: 网络请求失败 (curl exit: $CURL_EXIT)"
    exit 0
fi

if [ -z "$RESPONSE" ]; then
    echo "=== Semantic Scholar 搜索结果 ==="
    echo "ERROR: API 无响应"
    exit 0
fi

# 检查是否有错误（如限流）
if echo "$RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); sys.exit(0 if 'data' in d else 1)" 2>/dev/null; then
    :  # 有 data 字段，正常
else
    ERROR_MSG=$(echo "$RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('message','Unknown error'))" 2>/dev/null || echo "Unknown error")
    echo "=== Semantic Scholar 搜索结果 ==="
    echo "ERROR: $ERROR_MSG"
    exit 0
fi

# 用 python3 解析 JSON 并输出结构化结果
echo "$RESPONSE" | python3 -c "
import sys, json

data = json.load(sys.stdin)
total = data.get('total', 0)
papers = data.get('data', [])

print(f'=== Semantic Scholar 搜索结果 (共 {total} 条匹配, 显示 {len(papers)} 条) ===')
print()

for i, paper in enumerate(papers, 1):
    title = paper.get('title', 'N/A')
    year = paper.get('year', 'N/A')
    paper_id = paper.get('paperId', 'N/A')
    citations = paper.get('citationCount', 0)
    url = paper.get('url', '')

    # 提取外部 ID
    ext_ids = paper.get('externalIds', {}) or {}
    arxiv_id = ext_ids.get('ArXiv', '')
    doi = ext_ids.get('DOI', '')

    # 提取作者
    authors = paper.get('authors', []) or []
    author_names = ', '.join([a.get('name', '') for a in authors[:5]])
    if len(authors) > 5:
        author_names += ' et al.'

    # PDF URL
    oa_pdf = paper.get('openAccessPdf', {}) or {}
    pdf_url = oa_pdf.get('url', '')

    # 如果有 arXiv ID 但没有 PDF URL，构造 arXiv PDF URL
    if not pdf_url and arxiv_id:
        pdf_url = f'https://arxiv.org/pdf/{arxiv_id}.pdf'

    print(f'--- 结果 {i} ---')
    print(f'TITLE: {title}')
    print(f'YEAR: {year}')
    print(f'AUTHORS: {author_names}')
    print(f'CITATIONS: {citations}')
    if arxiv_id:
        print(f'ARXIV_ID: {arxiv_id}')
    if doi:
        print(f'DOI: {doi}')
    if pdf_url:
        print(f'PDF_URL: {pdf_url}')
    else:
        print(f'PDF_URL: (无公开 PDF)')
    print(f'S2_URL: {url}')
    print()

print(f'TOTAL: {len(papers)}')
" 2>/dev/null

if [ $? -ne 0 ]; then
    echo "=== Semantic Scholar 搜索结果 ==="
    echo "ERROR: 解析响应失败"
    echo "原始响应前 500 字符:"
    echo "$RESPONSE" | head -c 500
    exit 0
fi
