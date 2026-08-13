# NetApp ShowMount Tool

This golang application queries via `GET` the NetApp [REST API](https://docs.netapp.com/us-en/ontap-restapi/ontap/getting_started_with_the_ontap_rest_api.html) to list volumes on a NetApp filer. This is similar to the `showmount` command and is useful for auto-discovery when `showmount` is disabled. During knfsd deployment, the listed volumes can be filtered via the `filter-exports` golang application. See [Export Configuration](../../../deployment/README.md#export-configuration) for further details.

The `netapp-exports` tool should be built locally and validated as working correctly with your NetApp storage before being used in the knfsd deployment.

```bash
cd /knfsd-file-cache/image/resources/netapp-exports
go build -o ~/netapp-exports
~/netapp-exports <options>
```

## Options

* `-config path`<br>
  Path to a config *.hcl file. This can be used as an alternative to specify the host, password, etc as command line options. Config files support listing multiple NetApp clusters in different locations.

* `-host string`<br>
  DNS or IP of the NetApp server (SVM endpoint). This is the DNS or IP name clients use when mounting the NFS shares.

* `-url string`<br>
  URL of the NetApp REST API (Management endpoint). This *must* include the API version and end with a slash, for example `https://netapp.example/api/v1/`.

* `-user string`<br>
  The username used to authenticate with the NetApp REST API.

* `-password string`<br>
  The password used to authenticate with the NetApp REST API. This option is not secure and is only intended for testing. For more secure options, use `-secret-name` or `-password-file`.

* `-password-file path`<br>
  A file containing the password to authenticate with the NetApp REST API.

* `-secret-region string`<br>
  The AWS region where AWS Secrets Manager is storing the NetApp password. The [default credential provider chain](https://docs.aws.amazon.com/sdkref/latest/guide/standardized-credentials.html#credentialProviderChain) is used to locate AWS credentials, including region, unless specifically overridden by this CLI option.

* `-secret-name string`<br>
  The name of an AWS Secrets Manager 'Secret' containing the NetApp REST API password.

* `-secret-version string`<br>
  The version of the AWS Secrets Manager 'Secret'. Defaults to `AWSCURRENT`.

* `-ca path`<br>
  Path to PEM encoded certificate file containing the root certificate for the NetApp REST API. This can also include intermediate certificates to provide the full certificate chain.

* `-insecure`<br>
  Allow insecure connections. This permits the use of the unencrypted `http` connections and ignores any certificate errors. This is only intended for testing as it can expose the password over an unencrypted connection, and encrypted connections will be vulnerable to man in the middle attacks.

* `-allow-common-name`<br>
  Allows using the Common Name (CN) field of the certificate as a DNS name when the certificate does not include a Subject Alternate Name (SAN) field. Use of the CN field is now deprecated as CN is ambiguous and only intended to provide a human readable name. However, some self-signed NetApp certificates still rely on the CN field. If the certificate contains a SAN then the CN will be ignored.

## Environment Variables

Alternatively, most of the options can be set using environment variables.

| Option               | Environment Variable       |
|----------------------|----------------------------|
| `-host`              | `NETAPP_HOST`              |
| `-url`               | `NETAPP_URL`               |
| `-user`              | `NETAPP_USER`              |
| `-password`          | `NETAPP_PASSWORD`          |
| `-password-file`     | `NETAPP_PASSWORD_FILE`     |
| `-secret-region`     | `NETAPP_SECRET_REGION`     |
| `-secret-name`       | `NETAPP_SECRET`            |
| `-secret-version`    | `NETAPP_SECRET_VERSION`    |
| `-ca`                | `NETAPP_CA`                |
| `-allow-common-name` | `NETAPP_ALLOW_COMMON_NAME` |

## Walk-through of configuring and testing `netapp-exports`

Here is a walk-through using 2 examples for how to extract the Certificate Authority (CA) certificate from a NetApp instance, configure the `netapp-exports` tool and run it locally to validate all is well before using it via the Terraform deployment tooling. This can be used to test that the tool can query a NetApp instance and produces the correct result. We interchangeably provide examples of both a CA signed certificate (Amazon FSx NetApp ONTAP) or a self-signed certificate (basic, on-premises, default). The NetApp password can be parsed to the golang `netapp-exports` application in 3 ways:

* `-secret-name` cli option or env var `NETAPP_SECRET`, stored in AWS Secrets Manager (recommended)
* `password-file` cli option or env var `NETAPP_PASSWORD_FILE` (not recommended)
* `-password` cli option or env var `NETAPP_PASSWORD` (not recommended, testing only)

> NOTE: For simplicity while testing in this walk-through, we will store the NetApp password in a file and later show how alternatively, it can be stored securely in AWS Secrets Manager. For production use it is advised to use AWS Secrets Manager to store the password.

It is beyond the scope of this documentation to cover all possible NetApp deployments (on-premises, other providers), so we will reference an already deployed [Amazon FSx for NetApp ONTAP](https://docs.aws.amazon.com/fsx/latest/ONTAPGuide/what-is-fsx-ontap.html) cluster in AWS for the CA signed certificate approach.

### Export the NetApp CA certificate (signed)

First you need the root CA certificate for your NetApp.

Set the `NETAPP` environment variable to the DNS name or IP that can be used to contact the NetApp cluster mgmt endpoint. In this example, we use `172.31.11.176` or `management.fs-01bdc7d55f4d23173.fsx.eu-west-2.amazonaws.com`.

```bash
ubuntu@knfsd-dev-ec2:~$ export NETAPP=management.fs-01bdc7d55f4d23173.fsx.eu-west-2.amazonaws.com

ubuntu@knfsd-dev-ec2:~$ openssl s_client -connect ${NETAPP}:443 </dev/null | openssl x509 > netapp.pem

depth=2 C = US, O = Amazon, OU = Amazon FSx, ST = Washington, CN = Amazon FSx Root CA 1 for eu-west-2, L = Seattle
verify error:num=19:self-signed certificate in certificate chain
verify return:1
depth=2 C = US, O = Amazon, OU = Amazon FSx, ST = Washington, CN = Amazon FSx Root CA 1 for eu-west-2, L = Seattle
verify return:1
depth=1 C = US, O = Amazon, OU = Amazon FSx, ST = Washington, CN = FSx CA for ONTAP-1 in eu-west-2, L = Seattle
verify return:1
depth=0 C = US, ST = Washington, L = Seattle, O = Amazon FSx, CN = management.fs-01bdc7d55f4d23173.fsx.eu-west-2.amazonaws.com
verify return:1
DONE
```

Verify that the certificate was downloaded:

```bash
ubuntu@knfsd-dev-ec2:~$ openssl x509 -in netapp.pem -noout -issuer -subject

issuer=C = US, O = Amazon, OU = Amazon FSx, ST = Washington, CN = FSx CA for ONTAP-1 in eu-west-2, L = Seattle
subject=C = US, ST = Washington, L = Seattle, O = Amazon FSx, CN = management.fs-01bdc7d55f4d23173.fsx.eu-west-2.amazonaws.com
```

### Export the NetApp CA certificate (self-signed)

In this alternative example, the certificate is a self-signed certificate. The certificate only contains a common name based on the NetApp mgmt host name (`netapptest`) instead of the fully qualified domain name.

```bash
root@netapp-client:~$ export NETAPP=netapptest

root@netapp-client:~$ openssl s_client -connect ${NETAPP}:443 </dev/null | openssl x509 > netapp.pem

Can't use SSL_get_servername
depth=0 CN = netapptest, C = US
verify error:num=18:self signed certificate
verify return:1
depth=0 CN = netapptest, C = US
verify return:1
DONE
```

Verify that the certificate was downloaded:

```bash
root@netapp-client:~$ openssl x509 -in netapp.pem -noout -issuer -subject

issuer=CN = netapptest, C = US
subject=CN = netapptest, C = US
```

### Check NetApp's SSL certificate names (signed / self-signed)

If the certificate contains subject alternative names (SANs) `X509v3 Subject Alternative Name`, then you can use any of `DNS:` or `IP:` entries to access the NetApp REST API. NetApp [recommends](https://docs.netapp.com/us-en/ontap-automation/get-started/access_rest_api.html) you always target the cluster management address/IP as this will load balance API requests across all nodes and avoid nodes that are offline or experiencing connectivity issues. If you have multiple cluster management LIFs configured, they are all equivalent regarding access to the REST API.

#### Signed

```bash
ubuntu@knfsd-dev-ec2:~$ openssl s_client -connect ${NETAPP}:443 </dev/null 2>/dev/null | openssl x509 -noout -subject -nameopt sname -ext subjectAltName

subject=/C=US/ST=Washington/L=Seattle/O=Amazon FSx/CN=management.fs-01bdc7d55f4d23173.fsx.eu-west-2.amazonaws.com
X509v3 Subject Alternative Name:
    DNS:management.fs-01bdc7d55f4d23173.fsx.eu-west-2.amazonaws.com, DNS:node1.fs-01bdc7d55f4d23173.ontap.fsx.eu-west-2.amazonaws.com, DNS:node2.fs-01bdc7d55f4d23173.ontap.fsx.eu-west-2.amazonaws.com
```

#### Self-signed

```bash
root@netapp-client:~$ openssl s_client -connect ${NETAPP}:443 </dev/null 2>/dev/null | openssl x509 -noout -subject -nameopt sname -ext subjectAltName

subject=/CN=netapptest/C=US
```

If the output only contains a common name (`/CN=netapptest`) you will need to use this as the DNS name or IP address and include the `-allow-common-name` CLI option when you invoke the `netapp-exports` tool.

```bash
root@netapp-client:~$ nslookup netapptest
Server:     169.254.169.254
Address:    169.254.169.254#53

Non-authoritative answer:
Name:   netapptest.location.company.internal
Address: 10.164.0.116
```

## Run NetApp ShowMount tool

Create a NetApp user with permission to access the NetApp REST API. FSx for NetApp by default provides a `fsxadmin` user/role which can be used for initial testing, but this has unrestricted access to the ONTAP system. Please consult NetApp or [FSx for NetApp](https://docs.aws.amazon.com/fsx/latest/ONTAPGuide/roles-and-users.html) documentation for more information on [creating a user](https://docs.aws.amazon.com/fsx/latest/ONTAPGuide/create-new-ontap-users.html) with read-only, minimum access permissions.

Create a file named `netapp-password` containing the password for your NetApp user.

Set the environment variables for the tool:

```bash
# CA signed, FSx example
export NETAPP_HOST=svm-027acf10d2f3e10cf.fs-01bdc7d55f4d23173.fsx.eu-west-2.amazonaws.com
export NETAPP_URL=https://management.fs-01bdc7d55f4d23173.fsx.eu-west-2.amazonaws.com/api/v1/
export NETAPP_USER=fsxadmin
export NETAPP_PASSWORD_FILE=netapp-password
export NETAPP_CA=netapp.pem

# Self-signed
export NETAPP_HOST=netapptest
export NETAPP_URL=https://netapptest/api/v1/
export NETAPP_USER=admin
export NETAPP_PASSWORD_FILE=netapp-password
export NETAPP_CA=netapp.pem
```

Build `netapp-exports` binary and check the required files are present:

```bash
ubuntu@knfsd-dev-ec2:~$ cd /knfsd-file-cache/image/resources/netapp-exports
ubuntu@knfsd-dev-ec2:/knfsd-file-cache/image/resources/netapp-exports$ go build -o ~/netapp-exports

ubuntu@knfsd-dev-ec2:~$ ls
netapp-password  netapp.pem  netapp-exports
```

Run the tool:

```bash
ubuntu@knfsd-dev-ec2:~$ ./netapp-exports

svm-027acf10d2f3e10cf.fs-01bdc7d55f4d23173.fsx.eu-west-2.amazonaws.com /
svm-027acf10d2f3e10cf.fs-01bdc7d55f4d23173.fsx.eu-west-2.amazonaws.com /vol1
svm-027acf10d2f3e10cf.fs-01bdc7d55f4d23173.fsx.eu-west-2.amazonaws.com /vol2
svm-027acf10d2f3e10cf.fs-01bdc7d55f4d23173.fsx.eu-west-2.amazonaws.com /vol2/vol3
svm-027acf10d2f3e10cf.fs-01bdc7d55f4d23173.fsx.eu-west-2.amazonaws.com /vol4
```

### Common Name

In this example because NetApp is using a self-signed certificate that only contains a common name (CN), the command needs to include `-allow-common-name`.

```bash
root@netapp-client:~$ ./netapp-exports -allow-common-name

/
/archive
/home
/hotfiles
/pipeline
```

## Run `showmount`

`showmount` is an alternative way to list the NFS exports, but it is not always supported/could be disabled.

```bash
/sbin/showmount -e ${NETAPP_HOST}

Export list for netapptest:
/ 10.164.0.0/20
/archive 10.164.0.0/20
/home 10.164.0.0/20
/hotfiles 10.164.0.0/20
/pipeline 10.164.0.0/20
```

If `showmount` is not supported by the NFS server you will see the error:

```bash
clnt_create: RPC: Unknown host
```

You might also see this error:

```bash
clnt_create: RPC: Program not registered
```

This is caused by the NFS server not supporting NFSv3. Ensure `vers3=yes` is set in `/etc/nfs.conf.d/knfsd.conf` and is excluded from the `DISABLED_NFS_VERSIONS` parameter.

## AWS Secrets Manager

[AWS Secrets Manager](https://aws.amazon.com/secrets-manager/) allows you to securely store your NetApp user password to your NetApp REST API and control access via IAM permissions, which can be provided to the EC2 KNFSD instance via an IAM instance-role.

* Navigate to: AWS Console -> [AWS Secrets Manager](https://console.aws.amazon.com/secretsmanager) in your preferred choice of AWS region and AWS account.
* Click "Store a new secret", select "Secret type" as "Other type of secret".
* Enter: `secret` as the KEY.
* Enter: `<your-password>` as the VALUE. Click "Next".
* Enter: `netapp-password` as the "Secret name".

Remove the environment variable `NETAPP_PASSWORD_FILE` and replace with:

```bash
export NETAPP_USER= # name of NetApp user with read-only access to REST API, with password stored in AWS Secrets Manager
export NETAPP_SECRET=netapp-password # secret name of the AWS Secret
export NETAPP_SECRET_REGION= # required if secret stored in different AWS region to where the knfsd proxy is running
```

## Troubleshooting

### The NetApp certificate is not valid

If the NetApp certificate is not valid because:

* The DNS name of the certificate does not match the DNS name used to access the NetApp.
* The certificate has expired

You can ignore any SSL certificate errors using the `-insecure` option.

> WARNING: Using this option is vulnerable to man in the middle attacks and should not be used in production.

```bash
./netapp-exports -insecure
```
