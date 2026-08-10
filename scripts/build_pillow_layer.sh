#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LAYER_DIR="${ROOT_DIR}/layer"
PYTHON_DIR="${LAYER_DIR}/python"
ZIP_FILE="${LAYER_DIR}/pillow-layer.zip"

PILLOW_VERSION="12.1.1"

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
  "Pillow==${PILLOW_VERSION}"

echo "Removing generated Python bytecode..."

find "${PYTHON_DIR}" -type d -name "__pycache__" -prune -exec rm -rf {} +
find "${PYTHON_DIR}" -type f -name "*.pyc" -delete

echo "Creating deterministic ZIP archive..."

export PYTHON_DIR
export ZIP_FILE

python3 <<'PY'
import os
import stat
import zipfile
from pathlib import Path

python_dir = Path(os.environ["PYTHON_DIR"])
zip_file = Path(os.environ["ZIP_FILE"])

# ZIP timestamps cannot be earlier than 1980.
fixed_time = (2020, 1, 1, 0, 0, 0)

# Sort all files to guarantee deterministic archive ordering.
files = sorted(
    (path for path in python_dir.rglob("*") if path.is_file()),
    key=lambda path: path.relative_to(python_dir.parent).as_posix(),
)

with zipfile.ZipFile(
    zip_file,
    "w",
    compression=zipfile.ZIP_DEFLATED,
    compresslevel=9,
) as archive:
    for path in files:
        archive_name = path.relative_to(python_dir.parent).as_posix()

        info = zipfile.ZipInfo(
            archive_name,
            date_time=fixed_time,
        )

        info.compress_type = zipfile.ZIP_DEFLATED
        info.create_system = 3
        info.external_attr = (stat.S_IFREG | 0o644) << 16

        archive.writestr(
            info,
            path.read_bytes(),
            compress_type=zipfile.ZIP_DEFLATED,
            compresslevel=9,
        )
PY

echo
echo "Pillow Lambda layer created:"
ls -lh "${ZIP_FILE}"

echo
echo "SHA-256:"
shasum -a 256 "${ZIP_FILE}"
