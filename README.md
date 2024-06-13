# tfe-fdo-podman-aa
This is a repository that will install Podman in a test environment in Active/Active mode.


Here is the [Terraform Enterprise official documentation](https://developer.hashicorp.com/terraform/enterprise/flexible-deployments/install/podman/install)


## Pre-requisites

- [X] [Terraform Enterprise License](https://www.hashicorp.com/products/terraform/pricing)
- [X] [AWS Account](https://aws.amazon.com/free/?gclid=Cj0KCQiAy9msBhD0ARIsANbk0A9djPCZfMAnJJ22goFzJssB-b1RfMDf9XvUYa0NuQ8old01xs4u8wIaAts9EALw_wcB&trk=65c60aef-03ac-4364-958d-38c6ccb6a7f7&sc_channel=ps&ef_id=Cj0KCQiAy9msBhD0ARIsANbk0A9djPCZfMAnJJ22goFzJssB-b1RfMDf9XvUYa0NuQ8old01xs4u8wIaAts9EALw_wcB:G:s&s_kwcid=AL!4422!3!458573551357!e!!g!!aws%20account!10908848282!107577274535&all-free-tier.sort-by=item.additionalFields.SortRank&all-free-tier.sort-order=asc&awsf.Free%20Tier%20Types=*all&awsf.Free%20Tier%20Categories=*all)
- [X] [Terraform](https://www.terraform.io/downloads)


# Steps on how to use this repository

- Clone this repository:
```shell
git clone git@github.com:dlavric/tfe-fdo-podman-aa.git
```

- Go to the directory where the repository is stored:
```shell
cd tfe-fdo-podman-aa
```

- Have your TFE FDO License that you have purchased at hand for its value

- Create a file `variables.auto.tfvars` with the following content
```hcl
aws_region     = "eu-west-3"
tfe_version    = "v202405-1"
tfe_hostname   = "podmanaa.daniela.sbx.hashidemos.io"
tfe_subdomain  = "podmanaa"
tfe_domain     = "daniela.sbx.hashidemos.io"
email          = "yourname@email.com"
username       = "dlavric"
password       = "DanielaLavric"
bucket         = "daniela-podmanaa-bucket1"
key_pair       = "daniela-podmanaa-key"
enc_password   = "encpassword"
license_value  = "XY..."
db_identifier  = "daniela-db-podman"
db_name        = "danieladb"
db_username    = "postgres"
db_password    = "dbpassword"
prefix         = "daniela"
storage_bucket = "daniela-podmanaa-storage"
```

- Export your AWS environment variables
```shell
export AWS_ACCESS_KEY_ID=
export AWS_SECRET_ACCESS_KEY=
export AWS_SESSION_TOKEN=
```

- Download all the Terraform dependencies for modules and providers
```shell
terraform init
```

- Apply all the changes
```
terraform apply
```

- Check the number of resources:
```shell

Plan: 39 to add, 0 to change, 0 to destroy.

Changes to Outputs:
  + public_ip   = (known after apply)
  + ssh_connect = (known after apply)
  + url         = "https://podmanaa.daniela.sbx.hashidemos.io"

Do you want to perform these actions?
  Terraform will perform the actions described above.
  Only 'yes' will be accepted to approve.

  Enter a value: 
  ```

- Check the output of the `terraform apply`
```shell

```

- Wait a couple of minutes for TFE to become online

- Access the TFE environment at the following URL: https://podmanaa.daniela.sbx.hashidemos.io

- Login to TFE UI with the username and password setup in the `variables.auto.tfvars` file and create your organization

- Destroy you infrastructure
```shell
terraform destroy
```