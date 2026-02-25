# AWS Serverless Image Processing Pipeline

This project demonstrates a serverless, event-driven image processing pipeline built on AWS using Terraform.

## Architecture

1. Image uploaded to S3 (uploads bucket)
2. S3 triggers AWS Lambda
3. Lambda:
   - Downloads the image
   - Generates:
     - 256px thumbnail
     - 1024px resized image
   - Writes both to processed bucket
4. Logs written to CloudWatch

## Services Used

- Amazon S3
- AWS Lambda (Python 3.12)
- IAM (least privilege)
- CloudWatch Logs
- Terraform
- Lambda Layer (Pillow)

## Deployment

From the terraform directory:

terraform init  
terraform plan -out=tfplan  
terraform apply tfplan  

## Testing

UPLOADS_BUCKET=$(terraform output -raw uploads_bucket)  
PROCESSED_BUCKET=$(terraform output -raw processed_bucket)  

aws s3 cp ./test.jpg s3://$UPLOADS_BUCKET/test.jpg  

Verify output:

aws s3 ls s3://$PROCESSED_BUCKET/processed/thumb_256/  
aws s3 ls s3://$PROCESSED_BUCKET/processed/thumb_1024/  

## Teardown

aws s3 rm s3://$UPLOADS_BUCKET --recursive  
aws s3 rm s3://$PROCESSED_BUCKET --recursive  
terraform destroy  

## Future Enhancements

- Add Dead Letter Queue (SQS)
- Add structured JSON logging
- Add CI (GitHub Actions)
- Convert to container-based Lambda