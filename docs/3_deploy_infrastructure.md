# Step 3: Deploy Infrastructure
This step will create a new EKS cluster and deploy the application.

## Prerequisites
1. Follow 0_safety_first.md and rename the current git checkout directory to the environment name you are going to deploy, if you have not done so already. You may need to reconnect the remote development environment as the file contents are moved out of the current working directory.
2. Follow 2_publish_sapio_bls_container_image.md to publish the container image to ECR, if you have not done so already.
3. Ensure you have completed init terraform backend per instruction in 1_build_terraform_backend.md.
4. Ensure the EC2 is still attached to the expected IAM role with required permissions, as described in 1_build_terraform_backend.md.

## Domain Configuration
This script will require you to have a domain fully managed by Route53.

The simplest way to get such a domain is to buy a new domain in Route53 in AWS Console.
After logging in to AWS console, go to Route 53 click "Domains" => "Registered Domains".
Click "Register Domain". Find a good domain name to use for your deployment. Then buy the domain.

You will enter the full domain name inside the tfvars file to be created below.
For example, I bought "sapiodev.com" domain, so I will enter this in the tfvars file to be created below. 
```text
customer_owned_domain = "sapiodev.com"
```

When EKS are deployed, all deployments will have external URL exposed by this domain for all web servers that end user need to access.
For now, this means there will be 1 web server for onlyoffice, and 1 web server for main BLS.
At the end of the deployment you will see the address under the domain your end users can log in under the BLS link:
```text
==========================
🔄 Getting URL. Please stand by...⭐️ Here is the URL of you newly deployed application running on EKS:
💻    https://bls.dev.sapiodev.com/velox_portal    
⭐️ Here is the OnlyOffice URL your office need to whitelist as well:
💻    https://docs.dev.sapiodev.com
⏳ Please be patient. It may take up to a minute to become available
```
In the case above, the environment name is "dev", so the bls will be deployed to https://bls.dev.sapiodev.com/velox_portal
The domain has auto-managed ACM to provide SSL certificate renewal services.

## OnlyOffice Editions
By default, the script assumes you have access to Enterprise version of Onlyoffice and your AWS environment is granted access to their repo.
If this is not the case, you may change the OnlyOffice edition to another edition that suits you in tfvars.

## Create TFVARS file.
In terraform/environment folder, copy the template.tfvars or one of the preset environment tfvars, rename to the working directory name.
Set the **env_name** variable to the working directory name.

Set the **sapio_bls_docker_image** to the published ECR image URI. It should be a concatenation of the repo section and the tag section of the docker image you listed earlier.
If you forgot, you can use the following command to find out the docker image repo name and tag.
```shell
sudo docker image ls
```
The image path is in format of `<aws_account_id>.dkr.ecr.<region>.amazonaws.com/<image_name>:<tag>`.

Set the **analytic_server_docker_image** to the analytic server version corresponds to the platform version you have installed. You can browse the available versions in the [Dockerhub Repoistory](https://hub.docker.com/repository/docker/sapiosciences/sapio_analytics_server/tags).

Set the **sapio_server_license_data** to the base64 encoded license file content of "exemplar.license" that is shipped to you by Sapio. The license file must be entitling the AWS account and NOT the Mac Address. 
> 💡 TIP
> 
> To obtain the base64 encoded content, you can copy the license file to the remote development environment then run command "base64 exemplar.license -w 0" to get the encoded content.

Scan through all scaling variables to ensure they are set to your desired values.

## Run Script
Run starthere/deploy_cluster.sh to deploy the infrastructure.