import os
import io
import urllib.parse
from pathlib import Path

import boto3
from PIL import Image, ImageOps

s3 = boto3.client("s3")

DEST_BUCKET = os.environ["DEST_BUCKET"]
PREFIX_256 = os.environ.get("DEST_PREFIX_256", "processed/thumb_256/")
PREFIX_1024 = os.environ.get("DEST_PREFIX_1024", "processed/thumb_1024/")

SIZE_256 = int(os.environ.get("SIZE_256", "256"))
SIZE_1024 = int(os.environ.get("SIZE_1024", "1024"))

ALLOWED_EXTS = {".jpg", ".jpeg", ".png", ".gif", ".webp"}


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


def lambda_handler(event, context):
    records = event.get("Records", [])
    if not records:
        return {"statusCode": 200, "body": "No records"}

    for r in records:
        src_bucket = r["s3"]["bucket"]["name"]
        src_key = urllib.parse.unquote_plus(r["s3"]["object"]["key"])

        if src_key.endswith("/"):
            continue

        ext = Path(src_key).suffix.lower()
        if ext not in ALLOWED_EXTS:
            print(f"Skipping non-image key: {src_key}")
            continue

        filename_stem = Path(src_key).stem
        out_name = f"{filename_stem}.jpg"

        # Safety against accidental recursion if notifications are misconfigured later
        if src_bucket == DEST_BUCKET and (src_key.startswith(PREFIX_256) or src_key.startswith(PREFIX_1024)):
            print(f"Skipping already-processed object: {src_key}")
            continue

        print(f"Downloading s3://{src_bucket}/{src_key}")
        obj = s3.get_object(Bucket=src_bucket, Key=src_key)
        body = obj["Body"].read()

        with Image.open(io.BytesIO(body)) as img:
            img_256 = _resize_max(img.copy(), SIZE_256)
            jpeg_256 = _to_jpeg_bytes(img_256)
            key_256 = f"{PREFIX_256}{out_name}"
            print(f"Writing 256 thumbnail: s3://{DEST_BUCKET}/{key_256}")
            s3.put_object(Bucket=DEST_BUCKET, Key=key_256, Body=jpeg_256, ContentType="image/jpeg")

            img_1024 = _resize_max(img.copy(), SIZE_1024)
            jpeg_1024 = _to_jpeg_bytes(img_1024)
            key_1024 = f"{PREFIX_1024}{out_name}"
            print(f"Writing 1024 thumbnail: s3://{DEST_BUCKET}/{key_1024}")
            s3.put_object(Bucket=DEST_BUCKET, Key=key_1024, Body=jpeg_1024, ContentType="image/jpeg")

    return {"statusCode": 200, "body": "OK"}
