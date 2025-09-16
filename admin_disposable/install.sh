
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
sudo groupadd docker
sudo usermod -aG docker "$USER"
newgrp docker
RECEIVED=docker run hello-world
if [[ $RECEIVED == *"Hello from Docker!"* ]]; then
    echo "================================================="
    echo "✅ Docker is installed and running. Installing user added to docker group."
    echo "================================================="
else
    echo "🫵 Docker is not running. Please start Docker and try again."
    exit 1
fi