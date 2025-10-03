# Step 1: Build Admin Disposable EC2
An admin disposable EC2 instance is a temporary virtual machine that can be used for administrative tasks, such as software installation, configuration changes, or troubleshooting. This instance can be terminated after use to ensure security and cost-effectiveness.

## Warning
The instance will have many admin privileges, so it is crucial to follow best security practices, such as using strong passwords, enabling multi-factor authentication, and regularly updating the instance.

You can terminate the instance and remove the role after use if you are worried about security.

The terraform states are stored within S3 permanently, so the instance can be rebuilt at any time without loss of state.

## Prerequisites
- You have admin access to the AWS Management Console.
- You have permission to create and manage EC2 instances.
- You have permission to create policy, and assign policy to EC2.

This tutorial assumes you are not familiar with AWS, linux commands, and shell. We will be using Windows Server AMI to provide you with a desktop environment. If you are comfortable with linux commands, you can choose using Ubuntu AMI which is cheaper. In the end, they are all linux docker images containers, and linux terraform commands.

## Server Installation Steps
1. Navigate to the [AWS Management Console](https://aws.amazon.com/console/).
2. Go to the EC2 Dashboard.
3. Click on "Launch Instance". Select Ubuntu 22.04 LTS, 64-bit, c7i.xlarge or equivalent.
4. Generate a new key if you don't have one. Otherwise, you can use an existing key pair.
5. Allow SSH traffic from "My IP".
6. 100GB of gp3 storage should be plenty, you can **encrypt** it.
7. In "Number of Instances", make sure you select only 1 instance. Give this instance a name such as "sapio_eks_training_admin_disposable_ec2". Click "Launch Instance".
8. Enter the instance and go to "Connect" tab, enter "SSH Client" tab, copy the public DNS. Use putty to save a profile with the public DNS, username "ubuntu", and the private key you downloaded earlier.
9. Connect to the instance using putty.
```shell
git clone https://github.com/sapiosciences-dev/ez_sapio_aws_devdeploy.git # unless you have a fork.
cd admin_disposable
./make_policy.sh
cat sapio_eks_policy.json
```
Copy the policy to clipboard. Alternatively, download the policy using SFTP client.
10. In IAM console, create a policy "sapio-eks-admin-disposable", paste the policy you copied earlier, and create the policy. 
11. Go to EC2 console, select the instance you created earlier, click "Actions" -> "Security" -> "Modify IAM Role", click "Create Role", select "AWS Service" -> "EC2", click "Next: Permissions", search for the policy you created earlier, select it, click "Next: Tags", click "Next: Review", give the role a name such as "sapio-eks-admin-disposable-role", click "Create Role". Go back to the instance, select the role you just created, and click "Update IAM Role".
12. Run "install.sh" under admin_disposable folder to install AWS CLI, kubectl, eksctl, and helm.
> 💡 TIP
>
> To run a script, you can right-click it from Remote Development IDE project tree on the left, and then click the "Run" button.

> 💡 TIP
> 
> If you see a screen with GUI but without a mouse device in pycharm/intellij to interactive with the console GUI, you can use tab to navigate it within the terminal window.

## Client UI Workspace
1. Download PyCharm or IntelliJ Idea Community Edition.
2. Click "File => Remote Development".
3. Click "New Connection" to add a new SSH configuration, give it a name such as "sapio_eks_admin_disposable_ec2", enter the public DNS, username "ubuntu", and the private key you downloaded earlier.
4. Click "Test Connection" to confirm the connection is successful.
5. Click "OK" to save the configuration.
6. Click "File => Open Remote Project", select the configuration you just created, and click "OK".
7. Open the github repo you cloned earlier.
8. Install: Terraform and HCL, AWS, Docker, Shell Script marketplace addons on the **host** IDE.
9. In tools => Terraform and OpenTOFU set the Terraform path to "/usr/bin/terraform". Click "Test". You should see a green checkmark.