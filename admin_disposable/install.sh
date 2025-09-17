#!/usr/bin/env bash
set -euo pipefail
echo "================================================="
echo "🚀 Installing AWS CLI, Terraform, and Docker"
echo "👉 This script was prepared for Ubuntu 22.04+."
echo "🔴 If you are not using Ubuntu, EXIT NOW."
echo "================================================="
printf "Press [Enter] to continue..."
read -r

sudo apt-get update && sudo apt-get install -y gnupg software-properties-common

# Terraform key
wget -O- https://apt.releases.hashicorp.com/gpg | \
gpg --dearmor | \
sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg > /dev/null
gpg --no-default-keyring \
--keyring /usr/share/keyrings/hashicorp-archive-keyring.gpg \
--fingerprint
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(grep -oP '(?<=UBUNTU_CODENAME=).*' /etc/os-release || lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list

# Add Docker's official GPG key:
sudo apt-get update
sudo apt-get install ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add HELM
sudo apt-get install curl gpg apt-transport-https --yes
curl -fsSL https://packages.buildkite.com/helm-linux/helm-debian/gpgkey | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
echo "deb [signed-by=/usr/share/keyrings/helm.gpg] https://packages.buildkite.com/helm-linux/helm-debian/any/ any main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list

# Add the repository to Apt sources:
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update

# Remove all unoffical Docker versions from official apt.
for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do sudo apt-get remove $pkg; done
sudo apt install awscli terraform helm docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y

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