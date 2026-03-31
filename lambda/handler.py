import io
import json
import logging
import os
import time
import urllib.parse
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import boto3
from botocore.exceptions import BotoCoreError, ClientError
from PIL import Image, ImageOps, UnidentifiedImageError

logger = logging.getLogger()
logger.setLevel(os.environ.get("LOG_LEVEL", "INFO").upper())

s3 = boto3.client("s3")

DEST_BUCKET = os.environ["DEST_BUCKET"]
SOURCE_PREFIX = os.environ.get("SOURCE_PREFIX", "incoming/")
PREFIX_256 = os.environ.get("DEST_PREFIX_256", "processed/thumb_256/")
PREFIX_1024 = os.environ.get("DEST_PREFIX_1024", "processed/thumb_1024/")

SIZE_256 = int(os.environ.get("SIZE_256", "256"))
SIZE_1024 = int(os.environ.get("SIZE_1024", "1024"))
MAX_FILE_SIZE_MB = int(os.environ.get("MAX_FILE_SIZE_MB", "10"))

ALLOWED_EXTS = {
    ext.strip().lower()
    for ext in os.environ.get("ALLOWED_EXTENSIONS", ".jpg,.jpeg,.png,.gif,.webp").split(",")
    if ext.strip()
}


def log_event(level: str, message: str, **fields: Any) -> None:
    payload = {"message": message, **fields}
    line = json.dumps(payload, default=str)

    if level == "error":
        logger.error(line)
    elif level == "warning":
        logger.warning(line)
    else:
        logger.info(line)


def _resize_max(img: Image.Image, max_edge: int) -> Image.Image:
    w, h = img.size
    if max(w, h) <= max_edge:
        return img

    if w >= h:
        new_w = max_edge
        new_h = int(h * (max_edge / w))
    else:
        new_h = max_edge
        new_w = int(w * (max_edge / h))

    return img.resize((new_w, new_h), resample=Image.LANCZOS)


def _to_jpeg_bytes(img: Image.Image) -> bytes:
    img = ImageOps.exif_transpose(img)

    if img.mode in ("RGBA", "LA"):
        bg = Image.new("RGB", img.size, (255, 255, 255))
        bg.paste(img, mask=img.split()[-1])
        img = bg
    elif img.mode != "RGB":
        img = img.convert("RGB")

    buf = io.BytesIO()
    img.save(buf, format="JPEG", quality=85, optimize=True)
    return buf.getvalue()


def _parse_record(record: Dict[str, Any]) -> Tuple[str, str]:
    src_bucket = record["s3"]["bucket"]["name"]
    src_key = urllib.parse.unquote_plus(record["s3"]["object"]["key"])
    return src_bucket, src_key


def _build_output_names(src_key: str) -> Tuple[str, str]:
    path = Path(src_key)
    parent_slug = str(path.parent).replace("/", "-").strip("-")
    stem = path.stem

    # Avoid collisions for files with same name in different folders
    base = f"{parent_slug}-{stem}" if parent_slug and parent_slug != "." else stem

    out_name_256 = f"{base}-256.jpg"
    out_name_1024 = f"{base}-1024.jpg"
    return out_name_256, out_name_1024


def _is_supported_source_key(src_key: str) -> Tuple[bool, str]:
    if src_key.endswith("/"):
        return False, "directory_placeholder"

    if SOURCE_PREFIX and not src_key.startswith(SOURCE_PREFIX):
        return False, "outside_source_prefix"

    ext = Path(src_key).suffix.lower()
    if ext not in ALLOWED_EXTS:
        return False, "unsupported_extension"

    return True, "ok"


def _already_processed(src_bucket: str, src_key: str) -> bool:
    return src_bucket == DEST_BUCKET and (
        src_key.startswith(PREFIX_256) or src_key.startswith(PREFIX_1024)
    )


def _object_exists(bucket: str, key: str) -> bool:
    try:
        s3.head_object(Bucket=bucket, Key=key)
        return True
    except ClientError as exc:
        code = exc.response.get("Error", {}).get("Code", "")
        if code in ("404", "NoSuchKey", "NotFound"):
            return False
        raise


def _get_source_object(src_bucket: str, src_key: str) -> bytes:
    obj = s3.get_object(Bucket=src_bucket, Key=src_key)
    body = obj["Body"].read()

    max_bytes = MAX_FILE_SIZE_MB * 1024 * 1024
    if len(body) > max_bytes:
        raise ValueError(f"source object exceeds max size of {MAX_FILE_SIZE_MB} MB")

    return body


def _put_processed_object(dest_key: str, body: bytes, src_key: str) -> None:
    s3.put_object(
        Bucket=DEST_BUCKET,
        Key=dest_key,
        Body=body,
        ContentType="image/jpeg",
        Metadata={
            "source-key": src_key,
            "processed-by": "lambda-image-pipeline",
        },
    )


def _process_record(record: Dict[str, Any], aws_request_id: str) -> Dict[str, Any]:
    started = time.time()

    src_bucket, src_key = _parse_record(record)

    valid, reason = _is_supported_source_key(src_key)
    if not valid:
        log_event(
            "info",
            "Skipping object",
            request_id=aws_request_id,
            bucket=src_bucket,
            key=src_key,
            reason=reason,
        )
        return {"status": "skipped", "bucket": src_bucket, "key": src_key, "reason": reason}

    if _already_processed(src_bucket, src_key):
        log_event(
            "warning",
            "Skipping already processed object",
            request_id=aws_request_id,
            bucket=src_bucket,
            key=src_key,
        )
        return {"status": "skipped", "bucket": src_bucket, "key": src_key, "reason": "already_processed"}

    out_name_256, out_name_1024 = _build_output_names(src_key)
    key_256 = f"{PREFIX_256}{out_name_256}"
    key_1024 = f"{PREFIX_1024}{out_name_1024}"

    # Lightweight idempotency: skip if both outputs already exist
    if _object_exists(DEST_BUCKET, key_256) and _object_exists(DEST_BUCKET, key_1024):
        log_event(
            "info",
            "Skipping object because outputs already exist",
            request_id=aws_request_id,
            bucket=src_bucket,
            key=src_key,
            output_256=key_256,
            output_1024=key_1024,
        )
        return {"status": "skipped", "bucket": src_bucket, "key": src_key, "reason": "outputs_exist"}

    log_event(
        "info",
        "Downloading source object",
        request_id=aws_request_id,
        bucket=src_bucket,
        key=src_key,
    )

    body = _get_source_object(src_bucket, src_key)

    try:
        with Image.open(io.BytesIO(body)) as img:
            img_256 = _resize_max(img.copy(), SIZE_256)
            jpeg_256 = _to_jpeg_bytes(img_256)
            _put_processed_object(key_256, jpeg_256, src_key)

            img_1024 = _resize_max(img.copy(), SIZE_1024)
            jpeg_1024 = _to_jpeg_bytes(img_1024)
            _put_processed_object(key_1024, jpeg_1024, src_key)

    except UnidentifiedImageError as exc:
        raise ValueError(f"file is not a valid image: {exc}") from exc

    duration_ms = round((time.time() - started) * 1000, 2)

    log_event(
        "info",
        "Processed image successfully",
        request_id=aws_request_id,
        bucket=src_bucket,
        key=src_key,
        output_256=key_256,
        output_1024=key_1024,
        size_bytes=len(body),
        duration_ms=duration_ms,
    )

    return {
        "status": "processed",
        "bucket": src_bucket,
        "key": src_key,
        "output_256": key_256,
        "output_1024": key_1024,
        "duration_ms": duration_ms,
    }


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    records: List[Dict[str, Any]] = event.get("Records", [])
    request_id = getattr(context, "aws_request_id", "unknown")

    if not records:
        log_event("info", "No records received", request_id=request_id)
        return {
            "statusCode": 200,
            "body": json.dumps({"message": "No records", "processed": 0, "skipped": 0, "failed": 0}),
        }

    results = []
    processed = 0
    skipped = 0
    failed = 0

    for record in records:
        try:
            result = _process_record(record, request_id)
            results.append(result)

            if result["status"] == "processed":
                processed += 1
            else:
                skipped += 1

        except (KeyError, ValueError, ClientError, BotoCoreError, OSError) as exc:
            failed += 1
            error_result = {"status": "failed", "error": str(exc)}
            results.append(error_result)

            log_event(
                "error",
                "Failed to process record",
                request_id=request_id,
                error_type=type(exc).__name__,
                error=str(exc),
            )

    summary = {
        "summary": "Processing complete",
        "processed": processed,
        "skipped": skipped,
        "failed": failed,
        "results": results,
    }

    log_event("info", "Invocation summary", request_id=request_id, **summary)

    if failed > 0:
        raise RuntimeError(f"Invocation failed for {failed} record(s). See logs for details.")

    return {"statusCode": 200, "body": json.dumps(summary)}