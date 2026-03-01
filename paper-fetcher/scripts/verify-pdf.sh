#!/bin/bash
# PDF 文件验证脚本
# 用法: bash verify-pdf.sh <file_path>
#
# 验证内容:
# 1. 文件是否存在
# 2. 文件大小是否合理 (> 10KB)
# 3. 是否为有效 PDF (magic bytes 检查)
# 4. 输出文件信息
#
# 返回:
#   exit 0 + "VALID" = 有效 PDF
#   exit 1 + "INVALID_xxx" = 无效文件

set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

FILE_PATH="$1"

if [ -z "$FILE_PATH" ]; then
    echo "用法: $0 <file_path>"
    exit 1
fi

# 1. 检查文件是否存在
if [ ! -f "$FILE_PATH" ]; then
    echo -e "${RED}INVALID_NOT_FOUND${NC}: 文件不存在: $FILE_PATH"
    exit 1
fi

# 2. 检查文件大小
FILESIZE=$(stat -f%z "$FILE_PATH" 2>/dev/null || stat -c%s "$FILE_PATH" 2>/dev/null || echo "0")

if [ "$FILESIZE" -lt 10240 ]; then
    echo -e "${RED}INVALID_TOO_SMALL${NC}: 文件过小 (${FILESIZE} bytes)，可能不是有效论文 PDF"
    exit 1
fi

# 3. 检查 PDF magic bytes
HEADER=$(head -c 5 "$FILE_PATH" 2>/dev/null || echo "")

if ! echo "$HEADER" | grep -q "%PDF"; then
    # 检查是否是 HTML 错误页面
    if head -c 100 "$FILE_PATH" | grep -qi "<html\|<!DOCTYPE"; then
        echo -e "${RED}INVALID_HTML${NC}: 文件是 HTML 页面（可能是错误页或需要登录）"
    else
        echo -e "${RED}INVALID_NOT_PDF${NC}: 文件不是 PDF 格式"
    fi
    exit 1
fi

# 4. 输出文件信息
FILESIZE_KB=$((FILESIZE / 1024))
FILESIZE_MB=""
if [ "$FILESIZE_KB" -gt 1024 ]; then
    FILESIZE_MB=" ($(echo "scale=1; $FILESIZE / 1048576" | bc) MB)"
fi

echo -e "${GREEN}VALID${NC}: $(basename "$FILE_PATH") - ${FILESIZE_KB} KB${FILESIZE_MB}"
exit 0
