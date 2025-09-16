#!/usr/bin/env bash
set -euo pipefail
echo "📋 Sapio EZ EKS Application Deployment Prebuild Checklist:"
echo "👉 1. Ensure Dockerfile is present in the current directory."
echo "👉 2. Verify AWS CLI is configured with appropriate permissions."
echo "👉 3. Confirm you have access to the ECR repository."
echo "👉 4. Make sure Docker is installed and running."
echo "👉 5. Check platform version in argument of the Dockerfile."
echo "👉 6. Upload files/foundations.jar for the Sapio Foundations extractor to include in docker image."
echo "👉 7. Upload files/analytics.jar for the Sapio Analytics extractor to include in docker image."
echo "👉 8. Upload files/customizations.jar for the Sapio Customizations extractor to include in docker image. (Optional)"
printf "✅ If all checks are complete, press [Enter] to continue..."
read -r

if ! command -v aws &> /dev/null; then
    echo "🫵 AWS CLI is not installed. Please install AWS CLI and try again."
    exit 1
fi

docker='sudo docker'
if ! command -v docker &> /dev/null; then
    echo "🫵 Docker is not installed. Please install Docker and try again."
    exit 1
fi

SAPIO_ECR_NAME=659459510985.dkr.ecr.us-east-1.amazonaws.com
echo "================================================="
echo "🔐 Verifying AWS Account Entitlement with Sapio"
echo "================================================="
aws ecr get-login-password --region us-east-1 | $docker login --username AWS --password-stdin "${SAPIO_ECR_NAME}"
if [ $? -ne 0 ]; then
    echo "🫵 AWS Account is not entitled to access Sapio ECR. Please contact Sapio support."
    exit 1
fi
# Find the platform version to pull ARG SAPIO_PLATFORM_VERISON="2025.09.09.1949-1146-25_9"
SAPIO_PLATFORM_VERISON=$(grep 'ARG SAPIO_PLATFORM_VERISON=' Dockerfile | cut -d '=' -f2 | tr -d '"')
if [ -z "$SAPIO_PLATFORM_VERISON" ]; then
    echo "🫵 Could not find SAPIO_PLATFORM_VERISON in Dockerfile. Please ensure it is set correctly in Dockerfile."
    exit 1
fi
$docker pull "${SAPIO_ECR_NAME}/sapiosciences/sapio_platform/platform_default:${SAPIO_PLATFORM_VERISON}"
if [ $? -ne 0 ]; then
    echo "🫵 Failed to pull Sapio platform image. Please check the Sapio AWS entitlements."
    exit 1
fi

NAME=my-sapio-app-dev
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_NAME=${ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com
LATEST_TAG=${ECR_NAME}/${NAME}:latest
echo "================================================="
echo "✅ Received AWS Account ID: ${ACCOUNT_ID} from AWS STS"
echo "================================================="

echo "================================================="
echo "🚀 Building and Pushing Docker Image: ${LATEST_TAG}"
echo "================================================="
$docker build . -t "${LATEST_TAG}"

aws ecr get-login-password --region us-east-1 | $docker login --username AWS --password-stdin "${ECR_NAME}"
echo "================================================="
echo "✅ Logged in to ECR: ${ECR_NAME}"
echo "================================================="
# Check if ECR repo exists. If not, create a new ECR repo.
if ! aws ecr describe-repositories --repository-names "${NAME}" --region us-east-1 &> /dev/null; then
    echo "🆕 ECR repository ${NAME} does not exist. Creating a new repository."
    aws ecr create-repository --repository-name "${NAME}" --region us-east-1
    echo "✅ Created ECR repository: ${NAME}"
else
    echo "✅ ECR repository ${NAME} already exists."
fi
$docker push "${LATEST_TAG}"

echo "================================================="
echo "✅ Successfully pushed Docker Image: ${LATEST_TAG}"
echo "================================================="
echo "📌 Do you want to create a versioned tag? (y/n)"
read -r create_tag
if [[ $create_tag == "y" ]]; then
    echo "Enter the version tag (e.g., v1.0.0):"
    read -r version_tag
    VERSIONED_TAG=${ECR_NAME}/${NAME}:${version_tag}
    $docker tag "${LATEST_TAG}" "${VERSIONED_TAG}"
    $docker push "${VERSIONED_TAG}"
    echo "================================================="
    echo "✅ Successfully pushed Versioned Docker Image: ${VERSIONED_TAG}"
    echo "================================================="
else
    echo "Skipping versioned tag creation."
fi
echo "👋 Good bye!"