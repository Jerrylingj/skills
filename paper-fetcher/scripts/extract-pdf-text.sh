#!/bin/bash
# PDF 文本提取脚本
# 用法: bash extract-pdf-text.sh <file_path> [max_pages]
#
# 从 PDF 中提取文本内容，用于内容验证。
# 按优先级尝试多种方法，确保至少能提取到一些文本。
#
# 输出: 提取的文本内容（stdout）

set -euo pipefail

FILE_PATH="$1"
MAX_PAGES="${2:-3}"

if [ -z "$FILE_PATH" ]; then
    echo "用法: $0 <file_path> [max_pages]"
    echo "示例: $0 paper.pdf 3"
    exit 1
fi

if [ ! -f "$FILE_PATH" ]; then
    echo "ERROR: 文件不存在: $FILE_PATH"
    exit 1
fi

# 方法 1: pdftotext（最佳质量）
if command -v pdftotext &>/dev/null; then
    TEXT=$(pdftotext -f 1 -l "$MAX_PAGES" -layout "$FILE_PATH" - 2>/dev/null || echo "")
    if [ -n "$TEXT" ] && [ ${#TEXT} -gt 100 ]; then
        echo "=== 提取方法: pdftotext (前 ${MAX_PAGES} 页) ==="
        echo "$TEXT"
        exit 0
    fi
fi

# 方法 2: python3 + PyPDF2 或 pdfminer
if command -v python3 &>/dev/null; then
    TEXT=$(python3 -c "
import sys
try:
    from PyPDF2 import PdfReader
    reader = PdfReader('$FILE_PATH')
    pages = min($MAX_PAGES, len(reader.pages))
    for i in range(pages):
        text = reader.pages[i].extract_text()
        if text:
            print(text)
except ImportError:
    try:
        from pdfminer.high_level import extract_text
        text = extract_text('$FILE_PATH', page_numbers=list(range($MAX_PAGES)))
        print(text)
    except ImportError:
        sys.exit(1)
except Exception as e:
    sys.exit(1)
" 2>/dev/null || echo "")
    if [ -n "$TEXT" ] && [ ${#TEXT} -gt 100 ]; then
        echo "=== 提取方法: python3 (前 ${MAX_PAGES} 页) ==="
        echo "$TEXT"
        exit 0
    fi
fi

# 方法 3: strings 命令（最后的兜底方案）
# 虽然不够精确，但至少能提取一些可读文本
echo "=== 提取方法: strings (粗提取，可能不完整) ==="
strings "$FILE_PATH" | head -300

# 注意：如果上面所有方法都提取不到有意义的内容，
# SubAgent 应该根据文件名和搜索信息来判断论文正确性
