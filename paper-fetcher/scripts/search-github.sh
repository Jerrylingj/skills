#!/bin/bash
# GitHub 论文仓库搜索脚本
# 用法: bash search-github.sh "论文标题关键词" [max_results]
#
# 在 GitHub 上搜索论文对应的代码仓库
# 论文仓库的 README 通常包含 arXiv 链接
# 使用 GitHub Search API（无需 token，但有频率限制：10次/分钟）
# 输出: REPO / DESCRIPTION / ARXIV_IDS / STARS / URL

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

# 搜索关键词：论文标题 + arxiv 关键词提高精确度
SEARCH_QUERY="${QUERY} arxiv"
ENCODED_QUERY=$(urlencode "$SEARCH_QUERY")

API_URL="https://api.github.com/search/repositories?q=${ENCODED_QUERY}&sort=stars&order=desc&per_page=${MAX_RESULTS}"

RESPONSE=$(curl -L -s --max-time 30 \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "$API_URL" 2>/dev/null)

CURL_EXIT=$?

if [ $CURL_EXIT -ne 0 ] || [ -z "$RESPONSE" ]; then
    echo "=== GitHub 搜索结果 ==="
    echo "ERROR: 网络请求失败 (curl exit: $CURL_EXIT)"
    exit 0
fi

# 检查 API 限流
if echo "$RESPONSE" | grep -q '"message".*rate limit' 2>/dev/null; then
    echo "=== GitHub 搜索结果 ==="
    echo "ERROR: GitHub API 限流，请等待 1 分钟后重试"
    exit 0
fi

# 用 python3 解析结果，并尝试从 README 中提取 arXiv ID
echo "$RESPONSE" | python3 -c "
import sys, json, re

data = json.load(sys.stdin)
total = data.get('total_count', 0)
items = data.get('items', [])

print(f'=== GitHub 搜索结果 (共 {total} 条匹配, 显示 {len(items)} 条) ===')
print()

for i, repo in enumerate(items, 1):
    name = repo.get('full_name', 'N/A')
    desc = repo.get('description', '') or ''
    stars = repo.get('stargazers_count', 0)
    html_url = repo.get('html_url', '')
    topics = repo.get('topics', []) or []

    # 从描述中提取 arXiv ID
    arxiv_ids = re.findall(r'(\d{4}\.\d{4,5}(?:v\d+)?)', desc)

    # 从描述中提取 arXiv URL
    arxiv_urls = re.findall(r'arxiv\.org/abs/(\d{4}\.\d{4,5}(?:v\d+)?)', desc)
    arxiv_ids = list(set(arxiv_ids + arxiv_urls))

    print(f'--- 结果 {i} ---')
    print(f'REPO: {name}')
    print(f'STARS: {stars}')
    print(f'DESCRIPTION: {desc[:200]}')
    if topics:
        print(f'TOPICS: {\", \".join(topics[:10])}')
    if arxiv_ids:
        for aid in arxiv_ids:
            # 去掉版本号
            base_id = re.sub(r'v\d+$', '', aid)
            print(f'ARXIV_ID: {base_id}')
            print(f'PDF_URL: https://arxiv.org/pdf/{base_id}.pdf')
    else:
        print(f'ARXIV_ID: (需要查看 README 获取)')
        print(f'README_URL: {html_url}#readme')
    print(f'GITHUB_URL: {html_url}')
    print()

print(f'TOTAL: {len(items)}')

if len(items) > 0:
    no_arxiv = [repo for repo in items if not re.findall(r'\d{4}\.\d{4,5}', repo.get('description', '') or '')]
    if no_arxiv:
        print()
        print('提示: 以下仓库的描述中未直接包含 arXiv ID，可能需要查看 README:')
        for repo in no_arxiv[:3]:
            print(f'  - {repo[\"html_url\"]}')
" 2>/dev/null

if [ $? -ne 0 ]; then
    echo "=== GitHub 搜索结果 ==="
    echo "ERROR: 解析响应失败"
    echo "原始响应前 500 字符:"
    echo "$RESPONSE" | head -c 500
    exit 0
fi
