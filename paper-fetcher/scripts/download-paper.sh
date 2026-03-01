#!/bin/bash
# Paper Fetcher 统一下载脚本
# 用法:
#   bash download-paper.sh arxiv <arxiv_id> <output_path>
#   bash download-paper.sh openreview <forum_id> <output_path>
#   bash download-paper.sh url <pdf_url> <output_path>
#
# 所有下载都包含重试机制和基本验证

set -euo pipefail

# ===== 配置 =====
MAX_RETRIES=2
TIMEOUT=60
RETRY_DELAY=3
USER_AGENT="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

# ===== 颜色输出 =====
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# ===== 通用下载函数 =====
do_download() {
    local url="$1"
    local output="$2"
    local attempt=0

    # 确保输出目录存在
    mkdir -p "$(dirname "$output")"

    while [ $attempt -lt $MAX_RETRIES ]; do
        attempt=$((attempt + 1))
        log_info "下载尝试 ${attempt}/${MAX_RETRIES}: $(basename "$output")"

        if curl -L -f -s --max-time "$TIMEOUT" \
            -H "User-Agent: $USER_AGENT" \
            -o "$output" "$url"; then

            # 基本验证：检查文件存在且大小 > 10KB
            if [ -f "$output" ]; then
                local filesize
                filesize=$(stat -f%z "$output" 2>/dev/null || stat -c%s "$output" 2>/dev/null || echo "0")
                if [ "$filesize" -gt 10240 ]; then
                    # 检查是否为 PDF（magic bytes）
                    local header
                    header=$(head -c 5 "$output" 2>/dev/null || echo "")
                    if echo "$header" | grep -q "%PDF"; then
                        log_info "✅ 下载成功: $output ($(( filesize / 1024 )) KB)"
                        echo "DOWNLOAD_SUCCESS"
                        return 0
                    else
                        log_warn "文件不是有效 PDF，重试..."
                        rm -f "$output"
                    fi
                else
                    log_warn "文件过小 (${filesize} bytes)，可能是错误页面，重试..."
                    rm -f "$output"
                fi
            fi
        else
            log_warn "curl 下载失败"
        fi

        if [ $attempt -lt $MAX_RETRIES ]; then
            log_info "等待 ${RETRY_DELAY} 秒后重试..."
            sleep "$RETRY_DELAY"
        fi
    done

    log_error "❌ 下载失败: $url"
    rm -f "$output"
    echo "DOWNLOAD_FAILED"
    return 1
}

# ===== arXiv 下载 =====
download_arxiv() {
    local arxiv_id="$1"
    local output="$2"

    # 清理 arxiv_id：移除可能的前缀
    arxiv_id=$(echo "$arxiv_id" | sed 's/^arXiv://i' | sed 's/^https:\/\/arxiv\.org\/abs\///' | sed 's/^https:\/\/arxiv\.org\/pdf\///' | sed 's/\.pdf$//')

    local pdf_url="https://arxiv.org/pdf/${arxiv_id}.pdf"
    log_info "arXiv 下载: ${arxiv_id}"
    log_info "PDF URL: ${pdf_url}"

    do_download "$pdf_url" "$output"
}

# ===== OpenReview 下载 =====
download_openreview() {
    local forum_id="$1"
    local output="$2"

    # OpenReview PDF URL 格式
    local pdf_url="https://openreview.net/pdf?id=${forum_id}"
    log_info "OpenReview 下载: ${forum_id}"
    log_info "PDF URL: ${pdf_url}"

    do_download "$pdf_url" "$output"
}

# ===== 通用 URL 下载 =====
download_url() {
    local url="$1"
    local output="$2"

    log_info "URL 下载: ${url}"

    do_download "$url" "$output"
}

# ===== 主函数 =====
main() {
    if [ $# -lt 3 ]; then
        echo "用法:"
        echo "  $0 arxiv <arxiv_id> <output_path>"
        echo "  $0 openreview <forum_id> <output_path>"
        echo "  $0 url <pdf_url> <output_path>"
        echo ""
        echo "示例:"
        echo "  $0 arxiv 1706.03762 ~/Desktop/papers/attention.pdf"
        echo "  $0 openreview AbCdEfGh ~/Desktop/papers/paper.pdf"
        echo "  $0 url https://example.com/paper.pdf ~/Desktop/papers/paper.pdf"
        exit 1
    fi

    local command="$1"
    shift

    case "$command" in
        arxiv)
            download_arxiv "$1" "$2"
            ;;
        openreview)
            download_openreview "$1" "$2"
            ;;
        url)
            download_url "$1" "$2"
            ;;
        *)
            log_error "未知命令: $command"
            echo "支持的命令: arxiv, openreview, url"
            exit 1
            ;;
    esac
}

main "$@"
