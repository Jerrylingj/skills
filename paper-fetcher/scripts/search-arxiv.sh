#!/bin/bash
# arXiv 论文搜索脚本
# 用法: bash search-arxiv.sh "论文标题关键词" [max_results]
#
# 通过 arXiv API 搜索论文，返回结构化结果
# 输出格式: 每条结果一组，包含 TITLE / ARXIV_ID / PDF_URL / PUBLISHED 等

QUERY="${1:-}"
MAX_RESULTS="${2:-5}"

if [ -z "$QUERY" ]; then
    echo "用法: $0 \"论文标题关键词\" [max_results]"
    echo "示例: $0 \"Attention Is All You Need\" 3"
    exit 1
fi

# URL 编码函数：通过 stdin 传入避免引号注入
urlencode() {
    echo -n "$1" | python3 -c "import sys, urllib.parse; print(urllib.parse.quote(sys.stdin.read()))" 2>/dev/null \
        || echo -n "$1" | sed 's/ /%20/g; s/"/%22/g; s/#/%23/g; s/&/%26/g; s/+/%2B/g; s/:/%3A/g; s/'\''/%27/g'
}

ENCODED_QUERY=$(urlencode "$QUERY")

# ===== 尝试搜索 =====
# 先搜标题字段，失败则搜全文
search_arxiv() {
    local field="$1"  # ti 或 all
    local url="https://export.arxiv.org/api/query?search_query=${field}:${ENCODED_QUERY}&start=0&max_results=${MAX_RESULTS}&sortBy=relevance&sortOrder=descending"

    local response
    response=$(curl -L -s --max-time 30 "$url" 2>/dev/null)
    local curl_exit=$?

    if [ $curl_exit -ne 0 ]; then
        echo "CURL_ERROR:${curl_exit}" >&2
        return 1
    fi

    if [ -z "$response" ]; then
        return 1
    fi

    # 检查是否有结果（容错处理 grep 无匹配）
    local total
    total=$(echo "$response" | grep -o '<opensearch:totalResults[^>]*>[0-9]*' | grep -o '[0-9]*$' 2>/dev/null || echo "0")

    if [ "$total" = "0" ] || [ -z "$total" ]; then
        return 1
    fi

    echo "$response"
    return 0
}

# 先按标题搜索（保存退出码后再做其他赋值）
RESPONSE=$(search_arxiv "ti")
SEARCH_OK=$?
SEARCH_TYPE="标题搜索"

# 如果标题搜索无结果，回退到全文搜索
if [ $SEARCH_OK -ne 0 ] || [ -z "$RESPONSE" ]; then
    RESPONSE=$(search_arxiv "all")
    SEARCH_OK=$?
    SEARCH_TYPE="全文搜索"
fi

# 如果都没有结果
if [ $SEARCH_OK -ne 0 ] || [ -z "$RESPONSE" ]; then
    echo "=== arXiv 搜索结果 ==="
    echo "TOTAL: 0"
    echo "未找到匹配结果。"
    echo ""
    echo "建议:"
    echo "1. 简化搜索关键词（只保留论文标题核心词）"
    echo "2. 使用其他搜索脚本: search-semantic-scholar.sh, search-dblp.sh"
    exit 0
fi

TOTAL_RESULTS=$(echo "$RESPONSE" | grep -o '<opensearch:totalResults[^>]*>[0-9]*' | grep -o '[0-9]*$' 2>/dev/null || echo "?")

echo "=== arXiv 搜索结果 (${SEARCH_TYPE}, 共 ${TOTAL_RESULTS} 条匹配) ==="
echo ""

# 解析 XML 结果
# 注意: 只处理 <entry> 内的字段，忽略 feed 级别的 <title> 等
echo "$RESPONSE" | awk '
BEGIN { count = 0; in_entry = 0 }
/<entry>/ {
    in_entry = 1
    title = ""; id = ""; published = ""; updated = ""; summary = ""
    in_title = 0; in_summary = 0
}
# 只在 entry 内部处理 title
in_entry && !in_summary && /<title>/ {
    in_title = 1
    line = $0
    gsub(/.*<title>/, "", line)
    if (line ~ /<\/title>/) {
        gsub(/<\/title>.*/, "", line)
        title = line
        in_title = 0
    } else {
        title = line
    }
    next
}
in_title {
    if ($0 ~ /<\/title>/) {
        line = $0
        gsub(/<\/title>.*/, "", line)
        title = title " " line
        gsub(/^[ \t\n]+/, "", title)
        gsub(/[ \t\n]+$/, "", title)
        gsub(/[ \t\n]+/, " ", title)
        in_title = 0
    } else {
        title = title " " $0
    }
    next
}
in_entry && /<id>http/ {
    line = $0
    gsub(/.*<id>/, "", line)
    gsub(/<\/id>.*/, "", line)
    gsub(/^[ \t]+/, "", line)
    gsub(/[ \t]+$/, "", line)
    id = line
}
in_entry && /<published>/ {
    line = $0
    gsub(/.*<published>/, "", line)
    gsub(/<\/published>.*/, "", line)
    gsub(/^[ \t]+/, "", line)
    gsub(/[ \t]+$/, "", line)
    published = line
}
in_entry && /<updated>/ {
    line = $0
    gsub(/.*<updated>/, "", line)
    gsub(/<\/updated>.*/, "", line)
    gsub(/^[ \t]+/, "", line)
    gsub(/[ \t]+$/, "", line)
    updated = line
}
in_entry && /<summary>/ {
    in_summary = 1
    line = $0
    gsub(/.*<summary>/, "", line)
    if (line ~ /<\/summary>/) {
        gsub(/<\/summary>.*/, "", line)
        summary = line
        in_summary = 0
    } else {
        summary = line
    }
    next
}
in_summary {
    if ($0 ~ /<\/summary>/) {
        line = $0
        gsub(/<\/summary>.*/, "", line)
        summary = summary " " line
        in_summary = 0
    } else {
        summary = summary " " $0
    }
    next
}
/<\/entry>/ {
    if (in_entry && id != "") {
        count++
        # 从 id URL 中提取 arXiv ID
        arxiv_id = id
        gsub(/https?:\/\/arxiv\.org\/abs\//, "", arxiv_id)
        # 提取不带版本号的基础 ID
        base_id = arxiv_id
        gsub(/v[0-9]+$/, "", base_id)

        # 清理 summary
        gsub(/^[ \t\n]+/, "", summary)
        gsub(/[ \t\n]+$/, "", summary)
        gsub(/[ \t\n]+/, " ", summary)

        printf "--- 结果 %d ---\n", count
        printf "TITLE: %s\n", title
        printf "ARXIV_ID: %s\n", base_id
        printf "ARXIV_ID_VERSIONED: %s\n", arxiv_id
        printf "PDF_URL: https://arxiv.org/pdf/%s.pdf\n", base_id
        printf "PUBLISHED: %s\n", published
        printf "UPDATED: %s\n", updated
        if (length(summary) > 300) {
            printf "SUMMARY: %s...\n", substr(summary, 1, 300)
        } else {
            printf "SUMMARY: %s\n", summary
        }
        printf "\n"
    }
    in_entry = 0
}
END {
    printf "TOTAL: %d\n", count
}'
