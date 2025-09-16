#!/usr/bin/env bash
set -euo pipefail
echo "================================================="
echo "🚀 Installing AWS CLI, Terraform, and Docker"
echo "================================================="
sudo apt-get update && sudo apt-get install -y gnupg software-properties-common
wget -O- https://apt.releases.hashicorp.com/gpg | \
gpg --dearmor | \
sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg > /dev/null
gpg --no-default-keyring \
--keyring /usr/share/keyrings/hashicorp-archive-keyring.gpg \
--fingerprint
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(grep -oP '(?<=UBUNTU_CODENAME=).*' /etc/os-release || lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update
sudo apt install awscli terraform docker.io -y

echo "================================================="
echo "✅ Installed AWS CLI, Terraform, and Docker"
echo "================================================="
echo "================================================="
echo "🚀 Verifying installations"
echo "================================================="
if ! command -v aws &> /dev/null; then
    echo "🫵 AWS CLI is not installed. Please install AWS CLI and try again"
    exit 1
fi

if ! command -v terraform &> /dev/null; then
    echo "🫵 Terraform is not installed. Please install Terraform and try again"
    exit 1
fi

if ! command -v docker &> /dev/null; then
    echo "🫵 Docker is not installed. Please install Docker and try again"
    exit 1
fi
# only if group docker does not exist
TARGET_USER="${SUDO_USER:-$USER}"

# 1) Ensure docker group exists
if ! getent group docker >/dev/null 2>&1; then
  echo "🚀 Creating docker group"
  sudo groupadd docker
fi

# 2) Add the *actual* user to docker group
echo "👤 Adding $TARGET_USER to docker group"
sudo usermod -aG docker "$TARGET_USER"

# 3) Ensure Docker is installed & running (adjust if already handled)
if ! systemctl is-active --quiet docker; then
  echo "🔧 Starting Docker service"
  sudo systemctl enable --now docker
fi

# 4) Test without logging out: run with docker group using 'sg'
echo "🧪 Testing Docker as $TARGET_USER via 'sg docker'"
if sudo -u "$TARGET_USER" sg docker -c 'docker run --rm hello-world' | grep -q "Hello from Docker!"; then
  echo "✅ Docker works. (Group membership will persist next login.)"
else
  echo "❌ Docker test failed. Try logging out/in or check Docker service logs."
  exit 1
fi

echo "✅✅✅ All admin disposable tools installed"