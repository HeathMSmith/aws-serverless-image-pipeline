#!/usr/bin/env python3

import argparse
import json
import sys
from typing import Any

import boto3
from botocore.exceptions import BotoCoreError, ClientError


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Replay one failed S3 event from an SQS DLQ by copying the original object to a new incoming key."
    )
    parser.add_argument("--queue-url", required=True, help="SQS DLQ URL")
    parser.add_argument(
        "--destination-prefix",
        default="incoming/replay/",
        help="Prefix to copy failed objects into for replay",
    )
    parser.add_argument(
        "--delete-message",
        action="store_true",
        help="Delete the DLQ message after successful replay",
    )
    parser.add_argument(
        "--max-messages",
        type=int,
        default=1,
        help="Number of DLQ messages to request (default: 1)",
    )
    return parser.parse_args()


def receive_messages(sqs_client: Any, queue_url: str, max_messages: int) -> list[dict[str, Any]]:
    response = sqs_client.receive_message(
        QueueUrl=queue_url,
        MaxNumberOfMessages=max_messages,
        WaitTimeSeconds=2,
        VisibilityTimeout=30,
    )
    return response.get("Messages", [])


def extract_s3_record(message_body: str) -> tuple[str, str]:
    payload = json.loads(message_body)
    records = payload.get("Records", [])
    if not records:
        raise ValueError("DLQ message body did not contain any S3 records")

    record = records[0]
    bucket = record["s3"]["bucket"]["name"]
    key = record["s3"]["object"]["key"]
    return bucket, key


def build_replay_key(original_key: str, destination_prefix: str) -> str:
    original_name = original_key.split("/")[-1]
    destination_prefix = destination_prefix.rstrip("/") + "/"
    return f"{destination_prefix}{original_name}"


def replay_object(s3_client: Any, bucket: str, source_key: str, destination_key: str) -> None:
    s3_client.copy_object(
        Bucket=bucket,
        CopySource={"Bucket": bucket, "Key": source_key},
        Key=destination_key,
        MetadataDirective="REPLACE",
        Metadata={
            "replayed-from": source_key,
            "replay-source": "sqs-dlq",
        },
    )


def delete_message(sqs_client: Any, queue_url: str, receipt_handle: str) -> None:
    sqs_client.delete_message(QueueUrl=queue_url, ReceiptHandle=receipt_handle)


def main() -> int:
    args = parse_args()

    sqs = boto3.client("sqs")
    s3 = boto3.client("s3")

    try:
        messages = receive_messages(sqs, args.queue_url, args.max_messages)
        if not messages:
            print("No DLQ messages available.")
            return 0

        for message in messages:
            receipt_handle = message["ReceiptHandle"]
            body = message["Body"]

            bucket, source_key = extract_s3_record(body)
            destination_key = build_replay_key(source_key, args.destination_prefix)

            print(json.dumps({
                "action": "replay_start",
                "bucket": bucket,
                "source_key": source_key,
                "destination_key": destination_key,
            }))

            replay_object(s3, bucket, source_key, destination_key)

            print(json.dumps({
                "action": "replay_success",
                "bucket": bucket,
                "source_key": source_key,
                "destination_key": destination_key,
            }))

            if args.delete_message:
                delete_message(sqs, args.queue_url, receipt_handle)
                print(json.dumps({
                    "action": "dlq_message_deleted",
                    "source_key": source_key,
                }))

        return 0

    except (ValueError, KeyError, ClientError, BotoCoreError) as exc:
        print(json.dumps({
            "action": "replay_failed",
            "error_type": type(exc).__name__,
            "error": str(exc),
        }), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())