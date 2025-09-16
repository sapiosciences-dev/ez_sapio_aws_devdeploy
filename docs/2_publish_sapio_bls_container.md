# Publishing Sapio BLS Container
This guide will walk you through the steps to publish a Sapio BLS container. Follow the instructions below to ensure a successful publication.

## Prerequisites
Before you begin, ensure you have the following:
1. Completed 1_deploy_sapio_bls_container.md and have a running disposable EC2 instance with the attached IAM role set on EC2, and completed the initial installation script.
2. Your AWS account have read access to the Sapio private ECR repo for platform images. Contact Sapio Support if you need assistance with this.

## Check Dockerfile
Adjust the SAPIO_PLATFORM_VERISON argument inside the Dockerfile to the installing version of the Sapio BLS platform.

## Download Sapio Foundations Extractor
Use either [Sapio Jenkins](https://jenkins.sapiosciences.com) if you have access as Sapio employee, or [Sapio Public Resources](https://resources.sapiosciences.com) to download the latest Sapio Foundations Extractor for the correct platform version.
You will be downloading the Sapio Foundations extractor along with Analytics extractor.
Rename the foundations extractor JAR file in the archive into "foundations.jar", place it under containers/sapio_bls/files.
Rename the analytics extractor JAR file in the archive into "analytics.jar", place it under containers/sapio_bls/files.
> 💡 TIP
>
> You can drag and drop the file directly into the remote development project tree.

## Compile customization Extractor (Optional)
If you have a Sapio Java maven complex project, complete the sapio-copy-dependencies goal after full compile, rename the extractor into "customization.jar", and place it under containers/sapio_bls/files.

## Rename Repository
In build_export.sh, you see that the default repo name is set to *my-sapio-app-dev*. Change it to your desired repository name.

However, if you have changed the repository name, you must mirror the changes into terraform/environment tfvar files under **sapio_bls_docker_image** variable. 

**This is a good time to git push to your private git repo. Note that the extractors are intentionally not under version control as they will be published into ECR repo after imaging.**

## Build Image
Run the *build_export.sh* under containers/sapio_bls folder to build the image and push it to ECR repo.

You will be asked for a tag. Usually you want to select "Yes" and name a tag.

For purpose of this tutorial, we assume "v1.0.0" as the tag.

After the image has been built, you can verify the image contents by running:
```shell
sudo docker image ls
```

You should see an image with the name you specified earlier, and the tag "v1.0.0".
Then run
```shell
sudo docker run -it --entrypoint bash <your-repo-name>:v1.0.0
```
You will be dropped into the container bash shell. You can run
```shell
ls
```
to inspect the content. Verify your addons directory under the default directory contains the extractor content you wanted to include.