#!/bin/bash

docker='docker'

NAME=my-sapio-app-dev
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_NAME=${ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com
LATEST_TAG=${ECR_NAME}/${NAME}:latest
echo "================================================="
echo "✅ Received AWS Account ID: ${ACCOUNT_ID} from AWS STS"
echo "================================================="
aws ecr get-login-password --region us-east-1 | $docker login --username AWS --password-stdin "${ECR_NAME}"
echo "================================================="
echo "✅ Logged in to ECR: ${ECR_NAME}"
echo "================================================="

echo "================================================="
echo "🚀 Building and Pushing Docker Image: ${LATEST_TAG}"
echo "================================================="
$docker build . -t "${LATEST_TAG}"
docker push "${LATEST_TAG}"

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
    docker push "${VERSIONED_TAG}"
    echo "================================================="
    echo "✅ Successfully pushed Versioned Docker Image: ${VERSIONED_TAG}"
    echo "================================================="
else
    echo "Skipping versioned tag creation."
fi
echo "👋 Good bye!"