#!/bin/bash
# Deploy FastAPI API to AWS Lambda
# Usage: ./deploy-api.sh [version_tag]
# Example: ./deploy-api.sh v1

set -e  # Exit on error

# Configuration
REGION="us-east-1"
PROJECT="healthcare-kb"
FUNCTION_NAME="${PROJECT}-fastapi"

# Get version tag (default: latest)
VERSION=${1:-latest}

echo "🚀 FastAPI Lambda Deploy - Version: $VERSION"
echo "================================================"

# Step 1: Get ECR repo URL from Terraform
echo "📦 Step 1/6: Getting ECR repository URL..."
ECR_REPO=$(cd infrastructure/terraform && terraform output -raw fastapi_ecr_url 2>/dev/null)
if [ -z "$ECR_REPO" ]; then
  echo "❌ Error: Could not get ECR URL. Run 'terraform apply' first to create Lambda infrastructure."
  exit 1
fi
echo "✅ ECR repo: $ECR_REPO"

# Step 2: ECR Login
echo "🔑 Step 2/6: ECR Login..."
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ECR_REPO > /dev/null 2>&1
echo "✅ ECR Login successful"

# Step 3: Build Lambda container image
echo "🔨 Step 3/6: Building Lambda container image..."
docker buildx build --platform linux/amd64 --provenance=false \
  -t $ECR_REPO:$VERSION \
  -f docker/lambda/Dockerfile \
  . 2>&1 | tail -5
echo "✅ Build complete"

# Step 4: Push to ECR
echo "📤 Step 4/6: Pushing to ECR..."
docker push $ECR_REPO:$VERSION 2>&1 | grep -E "(Pushed|exists|digest)" | tail -5
echo "✅ Push complete"

# Step 5: Update Lambda function code
echo "🔄 Step 5/6: Updating Lambda function..."
aws lambda update-function-code \
  --function-name $FUNCTION_NAME \
  --image-uri $ECR_REPO:$VERSION \
  --region $REGION > /dev/null 2>&1
echo "✅ Lambda update triggered"

# Step 6: Wait for Lambda update to complete
echo "⏳ Step 6/6: Waiting for Lambda update (60s max)..."
aws lambda wait function-updated-v2 \
  --function-name $FUNCTION_NAME \
  --region $REGION 2>/dev/null
echo "✅ Lambda function updated"

# Safety check: verify env vars are still intact after update
# update-function-code does NOT touch env vars, but guard against accidents.
ENV_COUNT=$(aws lambda get-function-configuration \
  --function-name $FUNCTION_NAME --region $REGION \
  --query 'length(Environment.Variables)' 2>/dev/null || echo 0)
if [ "$ENV_COUNT" -lt 5 ] 2>/dev/null; then
  echo ""
  echo "⚠️  WARNING: Lambda has only $ENV_COUNT env var(s) — expected ~19."
  echo "   Run 'cd infrastructure/terraform && terraform apply' to restore."
  echo "   Or manually re-set via: aws lambda update-function-configuration ..."
fi

# Test health endpoint
echo ""
echo "================================================"
echo "🎉 Deployment Complete!"

ALB_URL=$(cd infrastructure/terraform && terraform output -raw alb_url 2>/dev/null || echo "")
if [ -n "$ALB_URL" ]; then
  echo "📍 API URL: ${ALB_URL}/api"
  echo "📖 Docs:    ${ALB_URL}/api/docs"
  echo ""
  echo "🧪 Testing health endpoint..."
  curl -s "${ALB_URL}/api/health" 2>/dev/null | python3 -m json.tool 2>/dev/null || echo "   (Health check failed — Lambda may need a moment to warm up)"
else
  echo "📍 API URL: Check 'terraform output api_url'"
fi

echo ""
echo "📝 Quick test commands:"
echo "   # Get JWT token"
echo "   TOKEN=\$(curl -s -X POST ${ALB_URL}/api/v1/token \\"
echo "     -H 'Content-Type: application/json' \\"
echo "     -d '{\"username\":\"demo\",\"password\":\"demo\"}' | python3 -c \"import sys,json; print(json.load(sys.stdin)['access_token'])\")"
echo ""
echo "   # Query the API"
echo "   curl -s -X POST ${ALB_URL}/api/v1/query \\"
echo "     -H 'Content-Type: application/json' \\"
echo "     -H \"Authorization: Bearer \$TOKEN\" \\"
echo "     -d '{\"question\":\"dental services in Florida\",\"page_limit\":3}' | python3 -m json.tool"
echo "================================================"
