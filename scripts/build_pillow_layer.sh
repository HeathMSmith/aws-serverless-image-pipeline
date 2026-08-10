#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LAYER_DIR="${ROOT_DIR}/layer"
PYTHON_DIR="${LAYER_DIR}/python"
ZIP_FILE="${LAYER_DIR}/pillow-layer.zip"

echo "Building Pillow Lambda layer..."

rm -rf "${PYTHON_DIR}"
rm -f "${ZIP_FILE}"

mkdir -p "${PYTHON_DIR}"

python3 -m pip install \
  --platform manylinux2014_x86_64 \
  --implementation cp \
  --python-version 3.12 \
  --only-binary=:all: \
  --target "${PYTHON_DIR}" \
  "Pillow==12.1.1"

(
  cd "${LAYER_DIR}"
  zip -qr pillow-layer.zip python
)

echo
echo "Pillow Lambda layer created:"
ls -lh "${ZIP_FILE}"
