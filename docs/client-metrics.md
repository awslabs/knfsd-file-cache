# Client Metrics

The KNFSD Metrics Agent is designed so that it can be used on NFS clients (as well as the KNFSD proxies) to collect additional metrics to indicate the health of the KNFSD proxies.

The primary metrics from the clients is the round trip (RTT) and execution (EXE) times of the read/write requests. These indicate the total latency of client requests. At first the latency will be high as all requests need to go back to the source server. As more data is cached the latency of read requests should reduce as more requests are answered by the proxy.

These instructions only include the custom NFS metrics collected by the KNFSD Metrics Agent. For standard metrics, including network throughput, install the standard metrics agent for your system. On AWS, the [Amazon CloudWatch Agent](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/GettingStarted.html) is recommended (and already installed on the KNFSD proxy instances).

## Prerequisites

To build the metrics agent you will need [go 1.25](https://go.dev/) or later.

## Building the Agent

  ```bash
  cd image/resources/knfsd-metrics-agent
  go build
  ```

Go will automatically download all the modules required by the package.

The build will produce a single binary named `knfsd-metrics-agent`.

### Building from Secure Networks

If you cannot access the internet to fetch packages there are two main options:

* Use [GOPROXY](https://go.dev/ref/mod#module-proxy) with a private package repository.

* Use `go mod vendor` from an instance that does have internet access, see https://go.dev/ref/mod#vendoring. This will create a vendor directory with all the source code required that can then be checked into source control, or copied to the build instance.

Configuring a private package repository, or setting up vendoring is beyond the scope of this document and depends upon your specific environment.

## Configuring the Agent

The agent is configured using YAML config files, see the [KNFSD Metric Agent documentation](../image/resources/knfsd-metrics-agent/README.md) for the available configuration.

On AWS, a sample configuration is provided to get started, this is split into two config files, [common.yaml](../image/resources/knfsd-metrics-agent/config/common.yaml) and [client.yaml](../image/resources/knfsd-metrics-agent/config/client.yaml).

The agent can be started from the terminal with following command:

  ```bash
  sudo ./knfsd-metrics-agent --config config/common.yaml --config config/client.yaml
  ```

When running from the terminal to test the configuration it can be useful to change the `collection_interval` to `10s` and add the `debug` exporter to the pipeline.

### Other Environments

`common.yaml` and `client.yaml` are intended for running on AWS and reporting to Amazon CloudWatch.

If you are reporting to other systems such as Elasticsearch, or wish to run on other platforms such as on-prem then you can use these files as a template to get started.

The main elements you will need to reconfigure are:

* `resourcedetection.detectors` if you're running on a different platform. Alternatively, remove `resourcedetection` from the pipeline completely if your platform is not supported by the `resourcedetection` processor.

* Add a new exporter such as `prometheus`:
  * Add config for the exporter to the `exporters` section
  * Remove `awsemf` from the list of exporters in the pipeline
  * Add the new exporter to the pipeline

* `metricstransform` processor. This processor can be used to rename the metrics and/or attributes to match the naming convention of your platform.

## Installing the Agent

Installing the agent on a client assumes the client uses the Linux OS with `systemd`.

* Copy the `knfsd-metrics-agent` compiled binary into `/usr/local/bin`
* Create the config directory `/etc/knfsd-metrics-agent`
* Copy the config files to `/etc/knfsd-metrics-agent`
* Copy and rename the [systemd/client.service](../image/resources/knfsd-metrics-agent/systemd/client.service) file to `/etc/systemd/system/knfsd-metrics-agent.service`
* Enable the agent: `systemctl enable knfsd-metrics-agent.service`

These installation steps should be included into your client image building process.

If running the commands by hand to test the process before building an image, remember to start the service:

* `systemctl start knfsd-metrics-agent.service`

To check the agent started successfully:

* `systemctl status knfsd-metrics-agent.service`
* `journalctl -o cat -u knfsd-metrics-agent.service`

## Example

The following example demonstrates how to install the `knfsd-metrics-agent` on an existing client instance.

* Steps marked with "(local)" should be executed from your local machine.
* Steps marked with "(remote)" should be executed on the remote EC2 instance (client).

### (local) Configure Environment

Set the following environment variables for use with the rest of the script (change the values to match your environment):

  ```bash
  export KNFSD_CLIENT_REGION=<region-name> # "us-east-1"
  export KNFSD_CLIENT_SUBNET=<subnet-id> # "id" of the private subnet where the EC2 instance will be launched
  export KNFSD_CLIENT_KEYPAIR=<keypair-name> # "name" of the RSA key created/uploaded to your AWS account
  export KNFSD_CLIENT_INSTANCE_TYPE=c6in.2xlarge
  ```

### (local) Create a client instance in AWS (Optional)

Normally these commands would be included as part of an existing process to build a client instance image.

To test these commands before including them to an existing process you can:

* Use an existing client instance (if so skip this step)
* Follow these steps to create a new instance

### (local) Create Security Group for SSH Access

It is beyond the scope of this documentation to describe all possible SSH setups that can work here and are compliant to your security policies. For further reading, please consult the AWS public docs on how you can [connect to your Linux instance](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/connect-to-linux-instance.html). One option is to provision an [Amazon EC2 Instance Connect (EIC) Endpoint](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/connect-with-ec2-instance-connect-endpoint.html) (free), which is explained further in the KNFSD [Developer](../docs/developer.md#remote-ssh-ec2-instance-connect-eic-endpoint) documentation.

For simplicity, this documentation provides an opinionated setup via an EC2 Security Group with SSH access from the public internet, allowlisted to your current IP address.

  ```bash
  vpc_id=$(aws ec2 describe-subnets --subnet-ids $KNFSD_CLIENT_SUBNET --query 'Subnets[0].VpcId' --output text)
  export KNFSD_CLIENT_SECURITY_GROUP_ID=$(aws ec2 create-security-group \
    --group-name "ssh-access-to-knfsd-client" \
    --vpc-id $vpc_id \
    --description "SSH access to KNFSD client machine" \
    --region $KNFSD_CLIENT_REGION \
    --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value="ssh-access-to-knfsd-client"}]" \
    --output text \
    --query 'GroupId')

  my_ip=$(curl -s https://checkip.amazonaws.com)/32
  aws ec2 authorize-security-group-ingress \
    --group-id $KNFSD_CLIENT_SECURITY_GROUP_ID \
    --protocol tcp \
    --port 22 \
    --cidr $my_ip \
    --region $KNFSD_CLIENT_REGION
  ```

### (local) Create a client instance in AWS

  ```bash
  export KNFSD_CLIENT_INSTANCE_ID=$(aws ec2 run-instances \
    --image-id resolve:ssm:/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id \
    --instance-type $KNFSD_CLIENT_INSTANCE_TYPE \
    --key-name $KNFSD_CLIENT_KEYPAIR \
    --subnet-id $KNFSD_CLIENT_SUBNET \
    --region $KNFSD_CLIENT_REGION \
    --associate-public-ip-address \
    --security-group-ids $KNFSD_CLIENT_SECURITY_GROUP_ID \
    --block-device-mappings '[
      {"DeviceName":"/dev/sda1","Ebs":{"VolumeSize":20,"VolumeType":"gp3","Encrypted":true,"DeleteOnTermination":true}}
      ]' \
    --metadata-options "HttpEndpoint=enabled,HttpTokens=required,HttpPutResponseHopLimit=2,InstanceMetadataTags=enabled" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value="knfsd-metrics-agent-client"}]" \
    --query 'Instances[0].InstanceId' \
    --output text)

  # short sleep to allow instance IP to be assigned
  sleep 5

  export KNFSD_CLIENT_INSTANCE_PUBLIC_IP=$(aws ec2 describe-instances --instance-ids $KNFSD_CLIENT_INSTANCE_ID --query 'Reservations[*].Instances[*].PublicIpAddress' --output text)
  ```

### (local) Checkout `knfsd-file-cache`

  ```bash
  git clone https://github.com/awslabs/knfsd-file-cache.git
  cd knfsd-file-cache
  git checkout v1.1.0 # or a different GitHub release TAG
  ```

### (local) Copy KNFSD Metrics Agent source code to the instance

Wait for the instance to be `Running` and `3/3 checks passed` in AWS Console.

  ```bash
  tar -czf knfsd-metrics-agent.tar.gz -C image/resources knfsd-metrics-agent
  scp -i /path/to/$KNFSD_CLIENT_KEYPAIR knfsd-metrics-agent.tar.gz ubuntu@$KNFSD_CLIENT_INSTANCE_PUBLIC_IP:/home/ubuntu
  ```

### (local) Connect to client instance

  ```bash
  ssh -i /path/to/$KNFSD_CLIENT_KEYPAIR ubuntu@$KNFSD_CLIENT_INSTANCE_PUBLIC_IP
  ```

### (remote) Download and install Golang

There are other methods to install Go. For simplicity, this example will install Go based on the [standard Go instructions](https://go.dev/doc/install).

  ```bash
  curl -fSLO https://go.dev/dl/go1.25.4.linux-amd64.tar.gz
  sudo rm -rf /usr/local/go
  sudo tar -C /usr/local -xzf go1.25.4.linux-amd64.tar.gz
  ```

Add Go to your path:

  ```bash
  export PATH="$PATH:/usr/local/go/bin"
  ```

Verify Go is installed:

  ```bash
  go version
  ```

### (remote) Build the KNFSD Metrics Agent

  ```bash
  tar -xzf knfsd-metrics-agent.tar.gz
  cd knfsd-metrics-agent
  go build -v
  ```

### (remote) Install the KNFSD Metrics Agent

  ```bash
  sudo chown root:root knfsd-metrics-agent
  sudo mv knfsd-metrics-agent /usr/local/bin
  sudo mkdir /etc/knfsd-metrics-agent
  sudo cp config/*.yaml /etc/knfsd-metrics-agent
  sudo cp systemd/client.service /etc/systemd/system/knfsd-metrics-agent.service
  ```

### (remote) Enable the KNFSD Metrics Agent

  ```bash
  sudo systemctl enable --now knfsd-metrics-agent.service
  ```

### (remote) Test the KNFSD Metrics Agent (Optional)

Check the KNFSD Metrics Agent is running:

  ```bash
  sudo systemctl -o cat status knfsd-metrics-agent.service
  ```

You should see output similar to:

  ```text
  ● knfsd-metrics-agent.service - Knfsd Metrics Agent
     Loaded: loaded (/etc/systemd/system/knfsd-metrics-agent.service; enabled; preset: enabled)
     Active: active (running) since Wed 2025-06-04 20:52:40 BST; 1h 35min ago
   Main PID: 606 (knfsd-metrics-a)
      Tasks: 13 (limit: 18821)
     Memory: 84.1M (peak: 87.6M)
        CPU: 901ms
     CGroup: /system.slice/knfsd-metrics-agent.service
             └─606 /usr/local/bin/knfsd-metrics-agent --config /etc/knfsd-metrics-agent/common.yaml --config /etc/knfsd-metrics-agent/client.yaml --config /etc/knfsd-metrics-agent/custom.yaml

    Started knfsd-metrics-agent.service - Knfsd Metrics Agent.
    2025-06-04T20:52:40.888+0100    info    service@v0.140.0/service.go:199 Setting up own telemetry...     {"resource": {}}
    2025-06-04T20:52:40.906+0100    info    service@v0.140.0/service.go:244 Skipped telemetry setup.        {"resource": {}}
    2025-06-04T20:52:40.906+0100    info    service@v0.140.0/service.go:266 Starting knfsd-metrics-agent... {"resource": {}, "Version": "1.1.0-alpha.17", "NumCPU": 8}
    2025-06-04T20:52:40.906+0100    info    extensions/extensions.go:41     Starting extensions...  {"resource": {}}
    2025-06-04T20:52:40.950+0100    info    service@v0.140.0/service.go:289 Everything is ready. Begin running and processing data. {"resource": {}}
  ```

Before viewing the metrics you will need to generate some NFS traffic. Mount an NFS share (via a KNFSD Proxy instance) and then read some data from the share.

For example, use the `dd` command to read a file from the NFS share.

  ```bash
  dd if=/mnt/nfs/share/example.file of=/dev/null bs=1M iflag=odirect
  ```

### (local) View the metrics

* Go to [CloudWatch](https://console.aws.amazon.com/cloudwatch/home), select "Metrics" > "All metrics" from the left-hand menu.

* Select one of the KNFSD metrics (e.g. `knfsd/metrics/mount/read_bytes`).

* Select "Actions" > "Add to dashboard" to add the metric to a new or existing CloudWatch dashboard.

**NOTE:** You may have to refresh the CloudWatch page if no data has been reported for the custom metric. Data should be reported within a few minutes once the agent is running.

### (local) Delete resources

Once you have finished testing the KNFSD Metrics Agent, delete the EC2 instance and security group:

  ```bash
  aws ec2 terminate-instances --region $KNFSD_CLIENT_REGION --instance-ids $KNFSD_CLIENT_INSTANCE_ID
  # optional
  aws ec2 delete-security-group --region $KNFSD_CLIENT_REGION --group-id $KNFSD_CLIENT_SECURITY_GROUP_ID
  ```
