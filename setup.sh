#!/bin/bash
set -e

echo "=== IDE Data Agent 环境初始化 ==="

# 1. 创建虚拟环境
if [ ! -d ".venv" ]; then
    echo "→ 创建虚拟环境..."
    python3 -m venv .venv
else
    echo "→ .venv 已存在，跳过创建"
fi

# 2. 安装依赖
echo "→ 安装依赖包..."
.venv/bin/pip install -r requirements.txt -q

# 3. 注册 Jupyter Kernel（项目级别）
echo "→ 注册 Jupyter Kernel..."
.venv/bin/python -m ipykernel install --prefix=.venv --name data-agent --display-name "Data Agent"

echo ""
echo "=== 初始化完成 ==="
echo "在 Kiro 中打开 notebooks/ 下的 .ipynb 文件"
echo "选择 .venv 对应的 Python 解释器即可运行"
