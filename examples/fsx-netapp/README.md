# FSx for NetApp ONTAP Example with Automated Export Discovery

Amazon [FSx for NetApp ONTAP](https://docs.aws.amazon.com/fsx/latest/NetAppONTAPGuide/what-is-fsx-ontap.html) is a fully managed file storage service that supports the industry-standard NFS protocol (v3, v4.0, v4.1, v4.2).

This advanced example provides a single KNFSD proxy connecting to a single-AZ FSx for NetApp ONTAP filesystem to act as the source filer. We enforce NFS v4.1 throughout the deployment, as the increase in filehandle size mandates the use of NFSv4.1.

This example uses an external FSID database (RDS PostgreSQL) to ensure consistent file handle allocation, which is the recommended approach for production deployments.

We use `dns_round_robin` traffic mode to best-effort load balance the NFS clients across the KNFSD proxies.

For more detailed information, see the [NetApp ShowMount Tool](../../image/resources/netapp-exports/README.md) documentation, which includes instructions on how to get the NetApp root CA certificate, and verify the `netapp-exports` command works for on-prem NetApp filers.

## Key Features

* **Automated Export Discovery**: Uses NetApp REST API to automatically discover and configure exports (`showmount` might be disabled or not work for FSx NetApp ONTAP)
* **Secure Credential Management**: NetApp admin password stored in AWS Secrets Manager
* **Automatic CA Certificate Extraction**: Download FSx for NetApp ONTAP CA certificate and inject into `var.NETAPP_CA` variable
* **Nested Volume Structure**: Demonstrates complex volume hierarchies with junction points

## FSx for NetApp ONTAP Configuration

This deployment creates:

* A single-AZ FSx for NetApp ONTAP filesystem with 2.5TB total storage capacity
* One Storage Virtual Machine (SVM)
* Five volumes (500GB each):
  * `/vol1` - Primary volume
  * `/vol1/vol2` - Junction point under vol1
  * `/vol3` - Independent volume  
  * `/vol3/vol4` - Junction point under vol3
  * `/vol3/vol4/vol5` - Junction point under vol3/vol4
* RESTful API enabled for management via `fsxadmin` user

There are a number of ways to [monitor](../../docs/check-startup.md) the deployment progress.

If deployment is successful (`knfsd-file-cache:status=ready`), you should see the following in the `/var/log/cloud-init-output.log` file via the `proxy-startup.sh` script:

```log
---- RUNNING: export netapp
Beginning processing of dynamically detected NetApp exports (ENABLE_NETAPP_AUTO_DETECT)...
Skipped "/", export was excluded
(Attempt 1/3) Mounting NFS share: svm-09679520c9ee88ca7.fs-0f2e8bf9a89f72a70.fsx.eu-west-2.amazonaws.com:/vol1...
NFS mount succeeded for svm-09679520c9ee88ca7.fs-0f2e8bf9a89f72a70.fsx.eu-west-2.amazonaws.com:/vol1
Creating NFS share export for /vol1...
Finished creating NFS share export for /vol1
(Attempt 1/3) Mounting NFS share: svm-09679520c9ee88ca7.fs-0f2e8bf9a89f72a70.fsx.eu-west-2.amazonaws.com:/vol1/vol2...
NFS mount succeeded for svm-09679520c9ee88ca7.fs-0f2e8bf9a89f72a70.fsx.eu-west-2.amazonaws.com:/vol1/vol2
Creating NFS share export for /vol1/vol2...
Finished creating NFS share export for /vol1/vol2
(Attempt 1/3) Mounting NFS share: svm-09679520c9ee88ca7.fs-0f2e8bf9a89f72a70.fsx.eu-west-2.amazonaws.com:/vol3...
NFS mount succeeded for svm-09679520c9ee88ca7.fs-0f2e8bf9a89f72a70.fsx.eu-west-2.amazonaws.com:/vol3
Creating NFS share export for /vol3...
Finished creating NFS share export for /vol3
(Attempt 1/3) Mounting NFS share: svm-09679520c9ee88ca7.fs-0f2e8bf9a89f72a70.fsx.eu-west-2.amazonaws.com:/vol3/vol4...
NFS mount succeeded for svm-09679520c9ee88ca7.fs-0f2e8bf9a89f72a70.fsx.eu-west-2.amazonaws.com:/vol3/vol4
Creating NFS share export for /vol3/vol4...
Finished creating NFS share export for /vol3/vol4
(Attempt 1/3) Mounting NFS share: svm-09679520c9ee88ca7.fs-0f2e8bf9a89f72a70.fsx.eu-west-2.amazonaws.com:/vol3/vol4/vol5...
NFS mount succeeded for svm-09679520c9ee88ca7.fs-0f2e8bf9a89f72a70.fsx.eu-west-2.amazonaws.com:/vol3/vol4/vol5
Creating NFS share export for /vol3/vol4/vol5...
Finished creating NFS share export for /vol3/vol4/vol5
Finished processing of dynamically detected NetApp exports (ENABLE_NETAPP_AUTO_DETECT)
---- DONE: 0h00m01s
...
INFO: Reached Proxy Startup Exit. Happy caching!
```

> NOTE: The Terraform `EXCLUDED_EXPORTS` variable is used to exclude the root export (`/`) from the export discovery, using the `filter_exports` Golang tool. See [Filter Patterns](../../deployment/docs/filter-patterns.md) for more details.

## Automated NetApp Integration

This example demonstrates the automated NetApp integration capabilities:

1. **Secrets Management**: The NetApp `fsxadmin` password is automatically stored in AWS Secrets Manager
2. **Certificate Management**: The FSx for NetApp ONTAP CA certificate is downloaded and injected into `NETAPP_CA` variable
3. **Export Discovery**: The Golang `netapp-exports` tool automatically discovers all available exports via the NetApp REST API
4. **Dynamic Configuration**: No manual `EXPORT_MAP` configuration needed - all exports are discovered automatically (without using `showmount`)

## Security Groups

This example creates a dedicated [security group](https://docs.aws.amazon.com/fsx/latest/ONTAPGuide/limit-access-security-groups.html) for the FSx for NetApp ONTAP filesystem (proxy to source), allowing inbound NFS traffic, and HTTPS for REST API access.

You will need to create or append to existing security group(s) for:

* NFS traffic; NFS clients to proxy ASG

See [Security Groups](../../deployment/docs/security-groups.md).

## Inputs

* `REGION` - (Required) The AWS region to use for deployment of the KNFSD File Cache. Example: `us-east-1`. No default.

* `SUBNET` - (Required) The single subnet ID to use for deployment of the FSx for NetApp ONTAP source filer and KNFSD File Cache. Example: `subnet-038e337f0ff4cd53f`. No default.

* `PROXY_AMI` - (Required) The AMI ID to use for the KNFSD caching proxy. This should be built using the Packer [image build](../../image/README.md) script. No default.

* `PROXY_BASENAME` - (Optional) Prefix used to name AWS resources. Every deployment in an AWS account MUST be given a unique basename to avoid conflicts (some of the resources created must have a globally unique name within an AWS account). Default: `nfsproxy`.

* `KEY_NAME` - (Optional) The name of the key pair to use for the KNFSD instances. Leave BLANK to use AWS SSM. Default: `""`.

* `INSTANCE_TYPE` - (Optional) The AWS EC2 instance type to use for the KNFSD cache. Default: `i3en.6xlarge`.

* `KNFSD_NODES` - (Optional) The number of KNFSD instances to deploy as part of the cluster. Default: `1`.

## Outputs

* `autoscaling_group_name` - Name of the KNFSD proxy Auto Scaling Group.

* `proxy_dns_name` - DNS name of the KNFSD proxy.

## NetApp Auto-Detection Configuration

The KNFSD deployment automatically configures the following NetApp parameters:

* `ENABLE_NETAPP_AUTO_DETECT` = true
* `NETAPP_HOST` = SVM NFS endpoint DNS name
* `NETAPP_URL` = Management endpoint REST API URL
* `NETAPP_USER` = "fsxadmin"
* `NETAPP_SECRET` = AWS Secrets Manager secret name
* `NETAPP_SECRET_REGION` = Deployment region
* `NETAPP_SECRET_VERSION` = "AWSCURRENT"
* `NETAPP_CA` = Downloaded FSx CA certificate from S3
* `NETAPP_ALLOW_COMMON_NAME` = false (FSx uses proper SAN certificates)

## CA Certificate

If running this example in a `GovCloud` or `AWS China` region, you will need to update the Terraform data source `"aws_ca_bundle"` to use the correct CA certificate bundle URL as per [AWS documentation](https://docs.aws.amazon.com/fsx/latest/ONTAPGuide/managing-resources-ontap-apps.html#netapp-ontap-api).

```bash
data "http" "aws_ca_bundle" {
  url = "https://fsx-aws-certificates.s3.amazonaws.com/bundle-${var.REGION}.pem" # Public AWS Regions
  # url = "https://fsx-aws-us-gov-certificates.s3.us-gov-west-1.amazonaws.com/bundle-${var.REGION}.pem" # AWSGovCloud Regions
  # url = "https://fsx-aws-cn-certificates.s3.cn-north-1.amazonaws.com.cn/bundle-${var.REGION}.pem" # AWS China Regions
}
```

## Security Considerations

1. **Password Security**: The NetApp `fsxadmin` password is stored securely in AWS Secrets Manager and accessed via IAM roles. For production workloads, the password should be stored outside of the Terraform state file.
2. **Principle of Least Privilege**: Consider creating a dedicated NetApp user with read-only REST API permissions instead of using `fsxadmin`.
3. **Certificate Validation**: Proper SSL certificate validation is enabled with downloaded CA certificate from S3.
4. **Network Security**: Security groups restrict access to only necessary ports and sources.

## Additional Notes

Depending on your chosen AWS region, you may be able to deploy the FSx for NetApp ONTAP filesystem with a different deployment type, such as `SINGLE_AZ_2` which provides a single-AZ (non-HA) deployment with NVMe L2ARC cache. See [AWS Regions](https://docs.aws.amazon.com/fsx/latest/NetAppONAPGuide/available-aws-regions.html) for more details.

Previously AWS authored blog posts on FSx for NetApp ONTAP, including the alternative `FlexCache` deployment approach using native NetApp ONTAP features, which now supports write-back mode:

* [Deploying Amazon FSx for NetApp ONTAP using HashiCorp Terraform](https://aws.amazon.com/blogs/storage/deploying-amazon-fsx-for-netapp-ontap-hashicorp-terraform/)
* [How to use NetApp ONTAP REST APIs with Amazon FSx for NetApp ONTAP](https://aws.amazon.com/blogs/storage/how-to-use-netapp-ontap-rest-apis-with-amazon-fsx-for-netapp-ontap/)
* [Caching data using Amazon FSx for NetApp ONTAP](https://aws.amazon.com/blogs/storage/caching-data-using-amazon-fsx-for-netapp-ontap/)
* [Amazon FSx for NetApp ONTAP now supports write-back mode for ONTAP FlexCache volumes](https://aws.amazon.com/about-aws/whats-new/2025/05/amazon-fsx-netapp-ontap-write-back-mode-ontap-flexcache-volumes/)
