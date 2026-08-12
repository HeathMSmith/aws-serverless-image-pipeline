# Event-Driven Serverless Image Pipeline on AWS with Terraform

A production-oriented serverless image processing pipeline built on AWS using Terraform. The project demonstrates event-driven processing with Amazon S3 and AWS Lambda, reusable dependency packaging through a Lambda Layer, asynchronous failure handling with an SQS dead-letter queue, CloudWatch observability, separate DEV and PROD Terraform environments, remote state, and controlled CI/CD through GitHub Actions and AWS OIDC.

The pipeline accepts image uploads under an `incoming/` prefix, invokes a Python 3.12 Lambda function, generates optimized 256px and 1024px JPEG derivatives, and writes the results to a separate processed-images bucket.

## Architecture

![AWS Serverless Image Pipeline Architecture](./assets/architecture/serverless-image-pipeline.png)

The primary runtime path is:

```text
User
  │
  ▼
S3 Upload Bucket
incoming/
  │
  ▼
S3 ObjectCreated Event
  │
  ▼
Lambda Processor
Python 3.12 + Pillow Layer
  │
  ├──► processed/thumb_256/
  │
  └──► processed/thumb_1024/
         │
         ▼
   S3 Processed Bucket
```

Failed asynchronous Lambda events are isolated through an SQS dead-letter queue and can be replayed by copying the original source object to a new `incoming/replay/` key.

CloudWatch provides centralized logs, Lambda error and duration alarms, and a dashboard for operational metrics.

## Processing Demonstration

### Original Image

![Original Image](./assets/screenshots/original.png)

### 256px Thumbnail

![256px Thumbnail](./assets/screenshots/thumb-256.png)

### 1024px Image

![1024px Image](./assets/screenshots/thumb-1024.png)

### CloudWatch Logs

![CloudWatch Logs](./assets/screenshots/logs.png)

The repository also includes additional upload and output screenshots under `assets/screenshots/`.

## How It Works

1. An image is uploaded to the uploads bucket under the configured `incoming/` prefix.
2. The S3 `ObjectCreated` notification invokes the Lambda processor.
3. The Lambda function validates and processes the image using Pillow.
4. The function generates:
   - a 256px derivative; and
   - a 1024px derivative.
5. The generated images are converted to optimized JPEG output.
6. Results are written to the processed-images bucket under:
   - `processed/thumb_256/`
   - `processed/thumb_1024/`
7. Logs and operational metrics are captured in CloudWatch.
8. Failed asynchronous invocations can be routed to the SQS DLQ for inspection and controlled replay.

## Data Flow

Default source prefix:

```text
incoming/
```

Default destination prefixes:

```text
processed/thumb_256/
processed/thumb_1024/
```

For an input object such as:

```text
incoming/example.png
```

the processor writes derived JPEG objects into the configured processed-image prefixes.

The Terraform variables enforce trailing slashes on the source and destination prefixes so event filtering and output paths remain predictable.

## Key Design Decisions

### Event-driven processing with S3

Amazon S3 provides the event source for the pipeline.

The uploads bucket notification is prefix-filtered so only objects under the configured source prefix invoke the Lambda processor. This avoids polling and keeps image processing reactive to object creation.

### Separate uploads and processed buckets

Raw uploads and processed outputs are stored in separate S3 buckets.

This design:

- avoids recursive processing triggers;
- creates a clear boundary between source and derived assets;
- allows independent lifecycle and access controls; and
- simplifies operational troubleshooting.

### Python 3.12 Lambda processor

The processor runs on AWS Lambda using:

```text
Python 3.12
```

The handler is:

```text
handler.lambda_handler
```

The Lambda deployment package is generated from `lambda/handler.py` through Terraform's Archive provider.

### Pillow Lambda Layer

Pillow is packaged separately as a Lambda Layer and attached to the processor.

This keeps the image-processing dependency separate from the application handler and makes the runtime dependency explicit in the infrastructure definition.

The shared GitHub Actions setup step runs:

```text
./scripts/build_pillow_layer.sh
```

before Terraform initialization so the Linux-compatible Pillow layer is available during CI/CD execution.

### Private and protected S3 storage

Both S3 buckets are configured with:

- Block Public Access;
- versioning;
- server-side encryption; and
- S3 object ownership controls.

The processed bucket also includes lifecycle management for generated objects.

### Idempotent processing

The processor includes checks intended to avoid unnecessary duplicate output work when derived objects already exist.

This is especially useful in event-driven systems where retries and repeated object events can occur.

## Failure Handling and Replay

### Asynchronous Lambda failures

The Terraform module configures Lambda asynchronous invocation behavior and an SQS dead-letter queue.

If asynchronous processing ultimately fails, the failed event can be isolated in the DLQ rather than being silently discarded.

### SQS dead-letter queue

The DLQ provides a bounded retention window for failed asynchronous events so they can be inspected and handled separately from successful processing.

The queue retention period is configurable through Terraform.

### Controlled replay

The repository includes:

```text
scripts/replay_dlq.py
```

The replay script reads failed S3 events from the DLQ and copies the original source object to a new replay key under:

```text
incoming/replay/
```

That new object creation re-enters the normal S3 event-processing path.

Example for DEV:

```bash
./scripts/replay_dlq.py   --queue-url "$(terraform -chdir=terraform/environments/dev output -raw lambda_dlq_url)"   --delete-message
```

Use the corresponding PROD environment output when operating against production.

The `--delete-message` option removes the DLQ message after a successful replay operation.

## Observability

CloudWatch resources are provisioned with the application rather than treated as an afterthought.

The module creates:

- a dedicated Lambda log group;
- configurable log retention;
- a Lambda Errors alarm;
- a Lambda Duration alarm; and
- a CloudWatch dashboard.

The dashboard includes operational views for:

```text
Invocations
Errors
Duration
Throttles
```

CloudWatch alarms can optionally publish alarm and recovery actions to an SNS topic when an `alarm_topic_arn` is supplied.

## IAM and Security

The Lambda processor uses an IAM execution role with scoped permissions for the resources required by the pipeline.

Permissions include access for:

- reading source objects from the uploads bucket;
- reading and writing processed objects;
- sending failed events to the SQS DLQ; and
- writing Lambda logs to CloudWatch Logs.

Additional security controls include:

- private S3 buckets;
- Block Public Access;
- no public processing endpoint;
- prefix-scoped S3 event notifications;
- server-side encryption for S3 data;
- GitHub Actions OIDC instead of stored AWS access keys; and
- encrypted remote Terraform state with native S3 state locking.

## Terraform Architecture

The reusable infrastructure module is located at:

```text
terraform/modules/image-pipeline/
├── cloudwatch.tf
├── iam.tf
├── lambda_async.tf
├── lambda.tf
├── locals.tf
├── main.tf
├── outputs.tf
├── s3.tf
├── sqs.tf
├── variables.tf
└── versions.tf
```

Separate environment roots are maintained under:

```text
terraform/environments/
├── dev/
└── prod/
```

Both environments currently require:

```text
Terraform >= 1.15.0
AWS provider ~> 6.0
Random provider ~> 3.5
Archive provider ~> 2.4
```

Each environment maintains its own dependency lockfile.

## Remote State

Terraform state is stored in the portfolio AWS account using an encrypted S3 backend.

```text
hms-terraform-state-portfolio
├── serverless-image-pipeline/dev/terraform.tfstate
└── serverless-image-pipeline/prod/terraform.tfstate
```

Native S3 locking is enabled with:

```hcl
use_lockfile = true
```

DEV and PROD therefore maintain separate remote state and locking.

## CI/CD with GitHub Actions

Terraform lifecycle operations are automated through GitHub Actions using AWS OIDC authentication rather than long-lived AWS access keys.

The shared Terraform setup action performs:

```text
AWS OIDC authentication
        │
        ▼
Terraform 1.15.3 setup
        │
        ▼
Build Pillow Lambda Layer
        │
        ▼
terraform init
        │
        ├── terraform fmt -check -recursive
        └── terraform validate
```

### Pull request planning

The Terraform Plan workflow runs for relevant Terraform, script, workflow, and shared-action changes.

For pull requests, the workflow:

1. authenticates to AWS using OIDC;
2. prepares the DEV Terraform environment;
3. builds the Pillow Lambda layer;
4. runs a Terraform plan; and
5. posts the plan output to the pull request as a sticky comment.

Manual workflow dispatch can also target DEV or PROD.

The plan workflow uses concurrency controls so superseded runs for the same pull request or environment can be cancelled.

### Controlled apply

Infrastructure deployment is performed through the manually triggered:

```text
Terraform Apply (Controlled)
```

workflow.

The selected DEV or PROD environment is associated with a GitHub Environment, allowing environment-specific controls and approval requirements.

The workflow:

1. runs only from `main`;
2. authenticates to AWS through OIDC;
3. prepares and validates the selected Terraform environment;
4. builds the Pillow layer;
5. creates a saved Terraform plan; and
6. applies that exact saved plan.

Apply concurrency is scoped by environment and does not cancel an in-progress deployment.

### Controlled destroy

Infrastructure teardown uses the manually triggered:

```text
Terraform Destroy (Controlled)
```

workflow.

The operator must enter:

```text
destroy
```

before the workflow proceeds.

The destroy process:

1. runs only from `main`;
2. creates a saved destroy plan;
3. renders the plan into the GitHub Actions job summary;
4. uploads the reviewed plan as a short-lived artifact;
5. downloads that artifact in the execution job; and
6. applies the exact reviewed destroy plan.

This separates destructive planning from execution.

## Deployment

GitHub Actions is the preferred deployment path because it exercises the repository's OIDC authentication, Pillow build process, environment controls, and saved-plan workflow.

Infrastructure can also be planned locally.

For DEV:

```bash
AWS_PROFILE=portfolio terraform -chdir=terraform/environments/dev init
AWS_PROFILE=portfolio terraform -chdir=terraform/environments/dev validate
AWS_PROFILE=portfolio terraform -chdir=terraform/environments/dev plan
```

For PROD:

```bash
AWS_PROFILE=portfolio terraform -chdir=terraform/environments/prod init
AWS_PROFILE=portfolio terraform -chdir=terraform/environments/prod validate
AWS_PROFILE=portfolio terraform -chdir=terraform/environments/prod plan
```

## Functional Testing

A simple development test can be performed by retrieving the uploads-bucket output and copying an image into the configured source prefix:

```bash
UPLOADS_BUCKET=$(terraform -chdir=terraform/environments/dev output -raw uploads_bucket)

AWS_PROFILE=portfolio aws s3 cp   ./test.jpg   "s3://$UPLOADS_BUCKET/incoming/test.jpg"
```

After Lambda processing completes, inspect the processed bucket:

```bash
PROCESSED_BUCKET=$(terraform -chdir=terraform/environments/dev output -raw processed_bucket)

AWS_PROFILE=portfolio aws s3 ls   "s3://$PROCESSED_BUCKET/processed/"   --recursive
```

The expected outputs are generated under the 256px and 1024px processed-image prefixes.

## Teardown

The preferred teardown path is the controlled GitHub Actions Destroy workflow.

Because S3 buckets may contain source, processed, or versioned objects, bucket contents can prevent Terraform from deleting a bucket. If teardown fails for that reason, inspect and intentionally remove the relevant bucket contents before retrying the reviewed destroy workflow.

For local administrative review, generate a destroy plan from the appropriate environment root:

```bash
AWS_PROFILE=portfolio terraform -chdir=terraform/environments/dev plan -destroy
```

Replace `dev` with `prod` when reviewing production teardown.

## Validation

The project has been exercised through Terraform planning, controlled deployment, image-processing tests, CloudWatch verification, and controlled teardown.

Validation has included:

- Terraform initialization and validation;
- DEV and PROD environment planning;
- GitHub Actions OIDC authentication;
- Docker-based Pillow layer preparation;
- controlled Terraform deployment;
- S3 event-triggered Lambda invocation;
- processing from the `incoming/` prefix;
- generation of 256px and 1024px JPEG derivatives;
- delivery to the processed-images bucket;
- CloudWatch log generation;
- Lambda error and duration monitoring;
- SQS DLQ provisioning;
- replay-script behavior;
- remote-state operation with native S3 locking; and
- controlled destroy-plan review and execution.

## Repository Structure

```text
.
├── .github/
│   ├── actions/
│   │   └── terraform-setup/
│   │       └── action.yml
│   └── workflows/
│       ├── terraform-apply.yml
│       ├── terraform-destroy.yml
│       └── terraform-plan.yml
├── assets/
│   ├── architecture/
│   │   └── serverless-image-pipeline.png
│   └── screenshots/
├── lambda/
│   └── handler.py
├── layer/
│   └── pillow-layer.zip
├── scripts/
│   ├── build_pillow_layer.sh
│   └── replay_dlq.py
├── terraform/
│   ├── environments/
│   │   ├── dev/
│   │   └── prod/
│   └── modules/
│       └── image-pipeline/
└── README.md
```

The generated Lambda package and Pillow layer contents are build artifacts and are ignored by Git according to the repository's `.gitignore`.

## Cost Considerations

The architecture is event-driven and does not require continuously running compute instances.

Primary cost drivers include:

- Lambda invocations, duration, and memory consumption;
- S3 storage, requests, and retained object versions;
- SQS requests and DLQ retention;
- CloudWatch logs, custom dashboard usage, and alarm metrics;
- optional SNS alarm notifications;
- Terraform remote-state storage; and
- standard AWS data-transfer charges.

DEV and PROD can remain destroyed when not needed for demonstration or testing.

## Lessons Learned

This project reinforced several practical serverless and infrastructure patterns:

- event-driven systems require deliberate retry and failure-handling design;
- SQS DLQs provide failure isolation but still require operational replay procedures;
- image-processing dependencies must be built for the Lambda runtime environment;
- S3 prefix filtering helps control event scope and prevents accidental processing;
- separate source and destination buckets simplify event boundaries;
- observability should be provisioned alongside the workload;
- remote state and locking are part of the infrastructure lifecycle;
- OIDC removes the need for stored AWS deployment credentials; and
- controlled saved-plan workflows improve confidence for both deployment and teardown.

## Future Improvements

Potential extensions include:

- KMS customer-managed keys for selected data or environment variables;
- DynamoDB metadata tracking for processed images;
- automated integration tests after deployment;
- richer alarm notification workflows;
- additional image transformations or output formats;
- multi-region processing patterns;
- automated DLQ replay controls with stronger operational safeguards; and
- application-level metrics for successful and failed image transformations.

## Tech Stack

**AWS | Terraform | S3 | Lambda | Python 3.12 | Pillow | SQS | CloudWatch | IAM | GitHub Actions | OIDC**

## Author

Heath Smith
