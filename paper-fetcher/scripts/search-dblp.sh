#!/bin/bash
# DBLP 论文搜索脚本
# 用法: bash search-dblp.sh "论文标题关键词" [max_results]
#
# 通过 DBLP API 搜索 CS 领域论文
# DBLP 是计算机科学领域最权威的文献索引之一
# 无需 API key，无频率限制
# 输出: TITLE / AUTHORS / YEAR / VENUE / DOI / DBLP_URL

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

API_URL="https://dblp.org/search/publ/api?q=${ENCODED_QUERY}&h=${MAX_RESULTS}&format=json"

RESPONSE=$(curl -L -s --max-time 30 \
    -H "Accept: application/json" \
    "$API_URL" 2>/dev/null)

CURL_EXIT=$?

if [ $CURL_EXIT -ne 0 ] || [ -z "$RESPONSE" ]; then
    echo "=== DBLP 搜索结果 ==="
    echo "ERROR: 网络请求失败 (curl exit: $CURL_EXIT)"
    exit 0
fi

# 用 python3 解析 JSON
echo "$RESPONSE" | python3 -c "
import sys, json

data = json.load(sys.stdin)
result = data.get('result', {})
hits = result.get('hits', {})
total = hits.get('@total', '0')
hit_list = hits.get('hit', [])

if isinstance(hit_list, dict):
    hit_list = [hit_list]

print(f'=== DBLP 搜索结果 (共 {total} 条匹配, 显示 {len(hit_list)} 条) ===')
print()

for i, hit in enumerate(hit_list, 1):
    info = hit.get('info', {})
    title = info.get('title', 'N/A')
    # DBLP 的 title 有时末尾带 '.'
    if title.endswith('.'):
        title = title[:-1]

    year = info.get('year', 'N/A')
    venue = info.get('venue', 'N/A')
    doi = info.get('doi', '')
    dblp_url = info.get('url', '')
    ee = info.get('ee', '')  # electronic edition URL

    # 作者处理（可能是字符串或列表）
    authors_raw = info.get('authors', {}).get('author', [])
    if isinstance(authors_raw, str):
        authors_raw = [authors_raw]
    elif isinstance(authors_raw, dict):
        authors_raw = [authors_raw.get('text', authors_raw.get('#text', str(authors_raw)))]

    author_names = []
    for a in authors_raw[:5]:
        if isinstance(a, dict):
            author_names.append(a.get('text', a.get('#text', str(a))))
        else:
            author_names.append(str(a))
    authors_str = ', '.join(author_names)
    if len(authors_raw) > 5:
        authors_str += ' et al.'

    print(f'--- 结果 {i} ---')
    print(f'TITLE: {title}')
    print(f'YEAR: {year}')
    print(f'AUTHORS: {authors_str}')
    print(f'VENUE: {venue}')
    if doi:
        print(f'DOI: {doi}')
    if ee:
        print(f'EE_URL: {ee}')
    if dblp_url:
        print(f'DBLP_URL: {dblp_url}')
    print()

print(f'TOTAL: {len(hit_list)}')
" 2>/dev/null

if [ $? -ne 0 ]; then
    echo "=== DBLP 搜索结果 ==="
    echo "ERROR: 解析响应失败"
    echo "原始响应前 500 字符:"
    echo "$RESPONSE" | head -c 500
    exit 0
fi
