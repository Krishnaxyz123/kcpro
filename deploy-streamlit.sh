#!/bin/bash
# Streamlit-Only Deploy Script for Healthcare Knowledge Base System
# Deploys ONLY the Streamlit app (ECS Fargate) — does NOT touch Terraform or Lambda
#
# Usage: ./deploy-streamlit.sh [version_tag]
# Example: ./deploy-streamlit.sh v-case-note

set -e  # Exit on error

# Configuration
ECR_REPO="<SANDBOX_ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/healthcare-kb-app"
REGION="us-east-1"
CLUSTER="healthcare-kb-cluster"
SERVICE="healthcare-kb-service"

VERSION=${1:-latest}

echo "🚀 Healthcare KB Streamlit Deploy - Version: $VERSION"
echo "================================================"

# Step 1: ECR Login
echo "📦 Step 1/4: ECR Login..."
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ECR_REPO > /dev/null 2>&1
echo "✅ ECR Login successful"

# Step 2: Build Streamlit Docker image
echo "🔨 Step 2/4: Building Streamlit image..."
docker buildx build --platform linux/amd64 --provenance=false \
  --build-arg BUILD_VERSION=$VERSION \
  -t $ECR_REPO:$VERSION \
  -f docker/backend/Dockerfile \
  backend/ 2>&1 | tail -5
echo "✅ Build complete"

# Step 3: Push to ECR
echo "📤 Step 3/4: Pushing image to ECR..."
docker push $ECR_REPO:$VERSION 2>&1 | grep -E "(Pushed|exists|digest)" | tail -5
echo "✅ Push complete"

# Step 4: Update ECS task definition with new image (no Terraform, no Lambda touch)
echo "🔄 Step 4/4: Updating ECS task definition..."

# Fetch current task definition
TASK_DEF_ARN=$(aws ecs describe-services \
  --cluster $CLUSTER \
  --services $SERVICE \
  --region $REGION \
  --query 'services[0].taskDefinition' \
  --output text)

TASK_DEF=$(aws ecs describe-task-definition \
  --task-definition $TASK_DEF_ARN \
  --region $REGION \
  --query 'taskDefinition')

# Build new task definition: swap image, strip read-only fields
NEW_TASK_DEF=$(echo $TASK_DEF | python3 -c "
import json, sys
td = json.load(sys.stdin)
for c in td.get('containerDefinitions', []):
    if 'healthcare-kb-app' in c.get('image', '') or c.get('name') in ('app', 'healthcare-kb-app', 'backend'):
        c['image'] = '$ECR_REPO:$VERSION'
        break
for key in ('taskDefinitionArn', 'revision', 'status', 'requiresAttributes',
            'compatibilities', 'registeredAt', 'registeredBy', 'deregisteredAt'):
    td.pop(key, None)
print(json.dumps(td))
")

# Register new revision
NEW_TASK_DEF_ARN=$(aws ecs register-task-definition \
  --region $REGION \
  --cli-input-json "$NEW_TASK_DEF" \
  --query 'taskDefinition.taskDefinitionArn' \
  --output text)

echo "   New task definition: $NEW_TASK_DEF_ARN"

# Update service to use new revision
aws ecs update-service \
  --cluster $CLUSTER \
  --service $SERVICE \
  --task-definition $NEW_TASK_DEF_ARN \
  --force-new-deployment \
  --region $REGION > /dev/null 2>&1

echo "✅ ECS deployment triggered"

# Wait for healthy ECS task
echo "⏳ Waiting for healthy ECS task (90s max)..."
for i in {1..18}; do
  sleep 5
  RUNNING=$(aws ecs describe-services \
    --cluster $CLUSTER \
    --services $SERVICE \
    --region $REGION \
    --query 'services[0].deployments[?status==`PRIMARY`].runningCount' \
    --output text 2>/dev/null)

  if [ "$RUNNING" == "1" ]; then
    echo "✅ ECS task is running!"
    break
  fi
  echo "   Still deploying... ($((i*5))s)"
done

echo ""
echo "================================================"
echo "🎉 Streamlit Deploy Complete!"
echo "📍 App: http://<APP_DOMAIN>"
echo "⚠️  Lambda/API unchanged — still on previous version"
echo "================================================"
