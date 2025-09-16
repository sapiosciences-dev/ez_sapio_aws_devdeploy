# Safety First
## Best Practices to Follow
1. Fork your own github repository to avoid any accidental changes to the original codebase to public.
2. Commit all changes to your private git repo. Store state changes to S3 bucket using the example backend storage for terraform.
3. Use a separate directory per environment, name your root checkout git directory the same name as env_name of the environment. Commit all environments to git. Avoid pushing dev to production by accident.
4. Discard the highly privileged but disposable EC2 instance after use. Terminate it and all EBS storage for the EC2. You can recreate it when needed quickly. Alternatively, remove the EC2 role assignment after use and reattach role when needed. 