#!/usr/bin/env bash

set -euo pipefail

# Verify Docker is installed and the daemon is available before starting the build.
if ! command -v docker >/dev/null 2>&1; then
    echo "ERROR: Docker is required to build the Pillow Lambda layer." >&2
    echo "Install Docker and rerun this script." >&2
    exit 1
fi

if ! docker info >/dev/null 2>&1; then
    echo "ERROR: Docker is installed, but the Docker daemon is not available." >&2
    echo "Start Docker Desktop (or your Docker daemon) and rerun this script." >&2
    exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LAYER_DIR="${ROOT_DIR}/layer"
PYTHON_DIR="${LAYER_DIR}/python"
ZIP_FILE="${LAYER_DIR}/pillow-layer.zip"

PILLOW_VERSION="12.1.1"

LAMBDA_IMAGE="public.ecr.aws/lambda/python@sha256:78a6662867dcca83dca5d950317c92c6ee8316199520b384a83f0d8e4874f6c6"

echo "Building Pillow Lambda layer..."
echo "Pillow version: ${PILLOW_VERSION}"
echo "Lambda build image: ${LAMBDA_IMAGE}"

rm -rf "${PYTHON_DIR}"
rm -f "${ZIP_FILE}"

mkdir -p "${PYTHON_DIR}"

echo "Installing Pillow inside the AWS Lambda Python 3.12 container..."

docker run --rm \
  --platform linux/amd64 \
  -v "${LAYER_DIR}:/layer" \
  --entrypoint /bin/bash \
  "${LAMBDA_IMAGE}" \
  -c "pip install \
    --no-compile \
    --target /layer/python \
    'Pillow==${PILLOW_VERSION}'"

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

# Sort files to guarantee deterministic archive ordering.
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
