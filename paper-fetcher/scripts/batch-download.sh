#!/bin/bash
# 批量论文下载脚本（一次调用下载所有论文）
# 用法: bash batch-download.sh <search_results_json> [output_dir]
#
# 输入: batch-search.sh 输出的 JSON 结果文件
# 功能: 读取所有 found 的论文，按顺序下载 PDF
#
# 一次 bash 调用完成所有下载，无需逐篇审批

RESULTS_FILE="${1:-}"
OUTPUT_DIR="${2:-/tmp/paper-fetcher-tmp}"

if [ -z "$RESULTS_FILE" ]; then
    echo "用法: $0 <search_results_json> [output_dir]"
    echo "示例: $0 /tmp/paper-fetcher-tmp/search_results.json ~/Desktop/papers"
    exit 1
fi

if [ ! -f "$RESULTS_FILE" ]; then
    echo "ERROR: 文件不存在: $RESULTS_FILE"
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 导出变量供 Python heredoc 使用
export RESULTS_FILE
export OUTPUT_DIR
export SCRIPT_DIR

python3 << 'PYTHON_SCRIPT'
import json
import subprocess
import sys
import os
import re
import time

RESULTS_FILE = os.environ.get("RESULTS_FILE", "")
OUTPUT_DIR = os.environ.get("OUTPUT_DIR", "/tmp/paper-fetcher-tmp")
SCRIPT_DIR = os.environ.get("SCRIPT_DIR", "")

with open(RESULTS_FILE, 'r') as f:
    results = json.load(f)

# 只下载有 PDF URL 的
downloadable = [r for r in results if r.get('status') == 'found' and r.get('pdf_url')]

print(f"📥 准备下载 {len(downloadable)} 篇论文...")
print(f"📂 输出目录: {OUTPUT_DIR}")
print()

def sanitize_filename(title, max_len=80):
    """清理标题为合法文件名"""
    name = re.sub(r'[/:*?"<>|\\]', '_', title)
    name = re.sub(r'\s+', '_', name)
    name = re.sub(r'_+', '_', name)
    name = name.strip('_')
    if len(name) > max_len:
        name = name[:max_len].rstrip('_')
    return name

download_results = []

for paper in downloadable:
    pid = paper['id']
    title = paper.get('matched_title') or paper.get('original_title', f'paper_{pid}')
    pdf_url = paper['pdf_url']
    arxiv_id = paper.get('arxiv_id', '')
    source = paper.get('source', 'url')
    
    # 生成文件名
    filename = f"{pid:02d}_{sanitize_filename(title)}.pdf"
    output_path = os.path.join(OUTPUT_DIR, filename)
    
    print(f"⬇️  [{pid}] {title[:50]}...")
    print(f"    URL: {pdf_url[:80]}")
    
    # 使用 download-paper.sh 脚本下载
    download_script = os.path.join(SCRIPT_DIR, 'download-paper.sh')
    
    if arxiv_id and source == 'arxiv':
        cmd = ['bash', download_script, 'arxiv', arxiv_id, output_path]
    else:
        cmd = ['bash', download_script, 'url', pdf_url, output_path]
    
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
        
        if os.path.exists(output_path) and os.path.getsize(output_path) > 10240:
            # 检查是否是 PDF
            with open(output_path, 'rb') as f:
                header = f.read(5)
            if header[:4] == b'%PDF':
                size_kb = os.path.getsize(output_path) // 1024
                print(f"    ✅ 成功 ({size_kb} KB) → {filename}")
                download_results.append({
                    'id': pid,
                    'filename': filename,
                    'path': output_path,
                    'status': 'success',
                    'size_kb': size_kb,
                })
            else:
                print(f"    ❌ 文件不是有效 PDF")
                os.remove(output_path)
                download_results.append({
                    'id': pid,
                    'filename': filename,
                    'status': 'invalid_pdf',
                })
        else:
            print(f"    ❌ 下载失败或文件过小")
            if os.path.exists(output_path):
                os.remove(output_path)
            download_results.append({
                'id': pid,
                'filename': filename,
                'status': 'failed',
            })
    except subprocess.TimeoutExpired:
        print(f"    ❌ 下载超时")
        download_results.append({
            'id': pid,
            'filename': filename,
            'status': 'timeout',
        })
    
    # 下载间隔，避免被限流
    time.sleep(1)
    print()

# 保存下载结果
dl_results_file = os.path.join(OUTPUT_DIR, 'download_results.json')
with open(dl_results_file, 'w') as f:
    json.dump(download_results, f, ensure_ascii=False, indent=2)

# 统计
success = sum(1 for r in download_results if r['status'] == 'success')
failed = len(download_results) - success

print(f"{'='*50}")
print(f"📊 下载完成: {success} 成功 / {failed} 失败")
print(f"📄 下载结果: {dl_results_file}")

if failed > 0:
    print()
    print("❌ 下载失败的论文:")
    for r in download_results:
        if r['status'] != 'success':
            print(f"   - [{r['id']}] {r['filename']} ({r['status']})")
PYTHON_SCRIPT
