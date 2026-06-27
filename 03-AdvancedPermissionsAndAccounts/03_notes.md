## AWS Organizations

- You can invite an existing or create a new AWS account
- Role switch in organization (Assumed role: OrganizationAccountAccessRole)

## SCP - Service Control Policies

- Allows restrictions to be placed on MEMBER accounts in the form of boundaries
- The MANAGEMENT account is not affected
- SCPs don't give permissions - they just control what an account CAN and CANNOT grant via identity policies.

## IAM Identity Center

- AWS Access Portal: https://daniel-dev.awsapps.com/start
- Users, Groups
- Permission Sets

```sh
$ aws configure sso
$ export AWS_PROFILE=xxx
$ aws sso login
$ aws sts get-caller-identity
```

## IAM Policy Evaluation

- Explicit Deny wins
- Explicit Allow
- Implicit Deny all
- Conditional policy

- A policy with only Deny blocks has no effect (because of the implicit Deny all)
- Inverse policy: `Action` => `NotAction`, `StringEquals` => `StringNotEquals`
