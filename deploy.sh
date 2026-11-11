#!/bin/bash
# Full Deploy Script for Healthcare Knowledge Base System
# Deploys both Streamlit (ECS Fargate) and FastAPI (Lambda)
#
# Usage: ./deploy.sh [version_tag]
# Example: ./deploy.sh v7

set -e  # Exit on error

# Configuration
ECR_REPO="<SANDBOX_ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/healthcare-kb-app"
REGION="us-east-1"
CLUSTER="healthcare-kb-cluster"
SERVICE="healthcare-kb-service"
LAMBDA_FUNCTION="healthcare-kb-fastapi"

# Get version tag (default: latest)
VERSION=${1:-latest}

echo "🚀 Healthcare KB Full Deploy - Version: $VERSION"
echo "================================================"

# =============================================================================
# Part 1: Streamlit (ECS Fargate)
# =============================================================================

# Step 1: ECR Login
echo "📦 Step 1/7: ECR Login..."
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ECR_REPO > /dev/null 2>&1
echo "✅ ECR Login successful"

# Step 2: Build Streamlit Docker image
echo "🔨 Step 2/7: Building Streamlit image..."
docker buildx build --platform linux/amd64 --provenance=false \
  --build-arg BUILD_VERSION=$VERSION \
  -t $ECR_REPO:$VERSION \
  -f docker/backend/Dockerfile \
  backend/ 2>&1 | tail -5

echo "✅ Build complete"

# Step 3: Push to ECR
echo "📤 Step 3/7: Pushing Streamlit image to ECR..."
docker push $ECR_REPO:$VERSION 2>&1 | grep -E "(Pushed|exists|digest)" | tail -5
echo "✅ Push complete"

# Step 4: Update terraform and deploy ECS
echo "🔄 Step 4/7: Deploying Streamlit to ECS..."

# Update terraform.tfvars with new version
TFVARS_FILE="infrastructure/terraform/terraform.tfvars"
sed -i.bak "s|app_image = \".*\"|app_image = \"$ECR_REPO:$VERSION\"|" $TFVARS_FILE
rm -f ${TFVARS_FILE}.bak

# Apply terraform
cd infrastructure/terraform
terraform apply -auto-approve > /dev/null 2>&1
cd ../..

# Force new deployment
aws ecs update-service \
  --cluster $CLUSTER \
  --service $SERVICE \
  --force-new-deployment \
  --region $REGION > /dev/null 2>&1

echo "✅ ECS deployment triggered"

# Step 5: Wait for healthy ECS task
echo "⏳ Step 5/7: Waiting for healthy ECS task (60s max)..."
for i in {1..12}; do
  sleep 5
  HEALTH=$(aws ecs describe-services \
    --cluster $CLUSTER \
    --services $SERVICE \
    --region $REGION \
    --query 'services[0].deployments[?status==`PRIMARY`].runningCount' \
    --output text 2>/dev/null)

  if [ "$HEALTH" == "1" ]; then
    echo "✅ ECS task is running!"
    break
  fi
  echo "   Still deploying... ($((i*5))s)"
done

# =============================================================================
# Part 2: FastAPI (Lambda)
# =============================================================================

echo ""
echo "🔄 Step 6/7: Deploying FastAPI Lambda..."

# Get FastAPI ECR repo URL from Terraform
ECR_REPO_API=$(cd infrastructure/terraform && terraform output -raw fastapi_ecr_url 2>/dev/null || echo "")

if [ -n "$ECR_REPO_API" ]; then
  # Build Lambda container image (build context is project root)
  docker buildx build --platform linux/amd64 --provenance=false \
    -t $ECR_REPO_API:$VERSION \
    -f docker/lambda/Dockerfile \
    . 2>&1 | tail -5

  # Push to ECR
  docker push $ECR_REPO_API:$VERSION 2>&1 | grep -E "(Pushed|exists|digest)" | tail -5

  # Update Lambda function code
  aws lambda update-function-code \
    --function-name $LAMBDA_FUNCTION \
    --image-uri $ECR_REPO_API:$VERSION \
    --region $REGION > /dev/null 2>&1

  # Wait for Lambda update
  echo "⏳ Step 7/7: Waiting for Lambda update..."
  aws lambda wait function-updated-v2 \
    --function-name $LAMBDA_FUNCTION \
    --region $REGION 2>/dev/null

  echo "✅ FastAPI Lambda deployed"
else
  echo "⏭️  FastAPI Lambda not configured (run terraform apply first), skipping"
fi

# =============================================================================
# Summary
# =============================================================================

echo ""
echo "================================================"
echo "🎉 Deployment Complete!"
echo "📍 Streamlit:  <ALB_HOSTNAME>"
echo "📍 API:        <ALB_HOSTNAME>/api"
echo "📖 API Docs:   <ALB_HOSTNAME>/api/docs"
echo "================================================"
