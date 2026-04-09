# Event-Driven Image Processing Pipeline on AWS (Terraform)

A production-grade, serverless image processing pipeline built on AWS using Terraform.

## What This Project Demonstrates
- Event-driven serverless architecture on AWS
- Infrastructure as Code (Terraform)
- Production-oriented design (IAM, observability, DLQ, idempotency)

---

## Architecture

Upload → S3 Event → Lambda → Process → Output Bucket

The diagram below illustrates the event-driven flow from S3 upload through Lambda processing and output storage, including DLQ and observability components.

![Architecture](./assets/architecture/serverless-image-pipeline.png)

---

## Architecture Decisions

### Why S3 Event Notifications?
S3 provides a native, scalable trigger mechanism that eliminates polling and enables immediate event-driven processing.

### Why AWS Lambda?
Lambda enables on-demand compute for burst workloads with no infrastructure management.

### Why Separate Buckets?
- Prevents recursive triggers  
- Isolates raw vs processed data  
- Improves security boundaries  

### Why Lambda Layers?
- Keeps deployment package small  
- Improves reusability  
- Simplifies dependency management  

### Why Terraform?
- Reproducible infrastructure  
- Version-controlled architecture  
- Environment consistency  

---

## How It Works

1. User uploads image to `incoming/`
2. S3 triggers Lambda (prefix-filtered)
3. Lambda:
   - Validates file type and size
   - Downloads image
   - Generates:
     - 256px thumbnail
     - 1024px resized image
   - Converts to optimized JPEG
4. Outputs written to:
   - `processed/thumb_256/`
   - `processed/thumb_1024/`
5. Logs, metrics, and alarms captured in CloudWatch

---

## Data Flow

- Input: `incoming/<filename>`
- Output:
  - `processed/thumb_256/<filename>-256.jpg`
  - `processed/thumb_1024/<filename>-1024.jpg`

---

## Key Features

- Fully serverless architecture
- Event-driven processing
- Prefix-filtered triggers
- Image resizing and optimization
- Idempotent processing (HeadObject checks)
- Structured logging
- CloudWatch alarms and dashboard
- SQS Dead Letter Queue (DLQ)
- Secure IAM (least privilege)
- Terraform IaC

---

## Observability

- Structured logs in CloudWatch
- Error tracking
- Duration monitoring
- Dashboard visualizing:
  - Invocations
  - Errors
  - Duration
  - Throttles

---

## Failure Handling

- Invalid files rejected
- Size limits enforced
- Errors logged with context
- Failed events sent to SQS DLQ
- Replay capability via script

---

## DLQ Replay

Replay failed events:

```bash
./scripts/replay_dlq.py   --queue-url "$(cd terraform && terraform output -raw lambda_dlq_url)"   --delete-message
```

---

## Demo

### Original Image
![Original](./assets/screenshots/original.png)

### 256px Thumbnail
![256](./assets/screenshots/thumb-256.png)

### 1024px Thumbnail
![1024](./assets/screenshots/thumb-1024.png)

### Logs
![Logs](./assets/screenshots/logs.png)

---

## Testing

```bash
UPLOADS_BUCKET=$(terraform output -raw uploads_bucket)
PROCESSED_BUCKET=$(terraform output -raw processed_bucket)

aws s3 cp ./test.jpg s3://$UPLOADS_BUCKET/incoming/test.jpg
```

---

## Deployment

```bash
cd terraform
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

---

## Teardown

To avoid ongoing charges, destroy all resources:

```bash
cd terraform
terraform destroy
```

If prompted, confirm with `yes`.

Note: Ensure no objects remain in S3 buckets if destroy fails due to non-empty buckets.

---

## Security Considerations

- S3 buckets are private with Block Public Access enabled
- Lambda execution role follows least-privilege principles
- S3 event notifications are prefix-scoped to avoid unintended triggers
- No public endpoints or direct access to processing components
- DLQ ensures failure isolation without data loss
- No long-lived credentials (designed for OIDC-based CI/CD integration)

Future improvement:
- KMS encryption for S3 and environment variables

---

## Cost Notes

This architecture is designed to operate within AWS Free Tier under low usage.

Estimated costs:
- Lambda: Free tier covers 1M requests/month
- S3:
  - Storage: ~$0.023/GB/month
  - Requests: minimal under low usage
- SQS (DLQ): negligible unless high failure volume
- CloudWatch:
  - Logs and metrics may incur small charges (~$1–$5/month depending on usage)

Typical monthly cost (light usage):
~$0 – $5

Cost optimization decisions:
- Serverless (no idle compute)
- Event-driven (no polling)
- Minimal storage footprint

---

## Future Enhancements

- CI/CD pipeline (GitHub Actions + OIDC)
- Multi-region deployment
- Advanced transformations
- Metadata tracking (DynamoDB)