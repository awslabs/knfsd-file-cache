/*
	Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
	SPDX-License-Identifier: Apache-2.0
*/

package smoke_tests

import (
	"context"
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"encoding/pem"
	"fmt"
	"os"
	"strings"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/ec2"
	ec2types "github.com/aws/aws-sdk-go-v2/service/ec2/types"
	"github.com/aws/aws-sdk-go-v2/service/ec2instanceconnect"
	"github.com/aws/aws-sdk-go-v2/service/ssm"
	ssmtypes "github.com/aws/aws-sdk-go-v2/service/ssm/types"
	"golang.org/x/crypto/ssh"
)

// statusTagKey is the EC2 tag the instance startup scripts use to advertise
// readiness. It mirrors the tag set by the KNFSD proxy and source-nfs module.
const statusTagKey = "knfsd-file-cache:status"

// sendEphemeralKey generates an in-memory RSA 2048-bit key pair, pushes the
// public half to the instance via EC2 Instance Connect (valid ~60s), and
// writes the private half to a 0600 temp file. The returned cleanup removes
// the temp file. The matching ssh/scp connection must be made within the
// 60-second window; once the SSH session is authenticated it survives the
// key's expiry.
func sendEphemeralKey(ctx context.Context, region, instanceID, osUser string) (keyPath string, cleanup func(), err error) {
	priv, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		return "", nil, fmt.Errorf("could not generate RSA key: %w", err)
	}

	pub, err := ssh.NewPublicKey(&priv.PublicKey)
	if err != nil {
		return "", nil, fmt.Errorf("could not derive SSH public key: %w", err)
	}
	authorizedKey := string(ssh.MarshalAuthorizedKey(pub))

	privPEM := pem.EncodeToMemory(&pem.Block{
		Type:  "RSA PRIVATE KEY",
		Bytes: x509.MarshalPKCS1PrivateKey(priv),
	})

	f, err := os.CreateTemp("", "ssm-ssh-key-*.pem")
	if err != nil {
		return "", nil, fmt.Errorf("could not create temp key file: %w", err)
	}
	keyPath = f.Name()
	cleanup = func() { _ = os.Remove(keyPath) }

	if err := os.Chmod(keyPath, 0o600); err != nil {
		_ = f.Close()
		cleanup()
		return "", nil, fmt.Errorf("could not chmod temp key file: %w", err)
	}
	if _, err := f.WriteString(string(privPEM)); err != nil {
		_ = f.Close()
		cleanup()
		return "", nil, fmt.Errorf("could not write temp key file: %w", err)
	}
	if err := f.Close(); err != nil {
		cleanup()
		return "", nil, fmt.Errorf("could not close temp key file: %w", err)
	}

	cfg, err := config.LoadDefaultConfig(ctx, config.WithRegion(region))
	if err != nil {
		cleanup()
		return "", nil, fmt.Errorf("could not load AWS config for region %s: %w", region, err)
	}

	// InstanceOSUser is the user whose authorized_keys the ephemeral key is added to.
	eic := ec2instanceconnect.NewFromConfig(cfg)
	if _, err := eic.SendSSHPublicKey(ctx, &ec2instanceconnect.SendSSHPublicKeyInput{
		InstanceId:     aws.String(instanceID),
		InstanceOSUser: aws.String(osUser),
		SSHPublicKey:   aws.String(authorizedKey),
	}); err != nil {
		cleanup()
		return "", nil, fmt.Errorf("could not push ephemeral SSH key to %s: %w", instanceID, err)
	}

	return keyPath, cleanup, nil
}

// proxyArgs returns the ssh/scp -o options that tunnel the connection over
// SSM (AWS-StartSSHSession) and authenticate with the ephemeral EIC key.
// %h resolves to the instance-id (the ssh "host") and %p to the port (22).
// Connection multiplexing collapses multiple commands to one instance into a
// single SSM tunnel and a single EIC key push.
func proxyArgs(region, keyPath, controlPath string) []string {
	proxy := fmt.Sprintf(
		"ProxyCommand=aws ssm start-session --target %%h "+
			"--document-name AWS-StartSSHSession --parameters portNumber=%%p --region %s",
		region,
	)
	return []string{
		"-i", keyPath,
		"-o", "IdentitiesOnly=yes",
		"-o", "AddKeysToAgent=no",
		"-o", proxy,
		"-o", "StrictHostKeyChecking=accept-new",
		"-o", "UserKnownHostsFile=/dev/null",
		"-o", "LogLevel=ERROR",
		"-o", "ControlMaster=auto",
		"-o", "ControlPath=" + controlPath,
		"-o", "ControlPersist=60s",
		"-o", "ConnectTimeout=30",
		"-o", "ServerAliveInterval=30",
		"-o", "ServerAliveCountMax=5",
	}
}

// waitInstanceOnline polls SSM until the instance's agent reports PingStatus
// Online (i.e. it is registered and reachable), or the timeout elapses.
func waitInstanceOnline(ctx context.Context, region, instanceID string, timeout time.Duration) error {
	cfg, err := config.LoadDefaultConfig(ctx, config.WithRegion(region))
	if err != nil {
		return fmt.Errorf("could not load AWS config for region %s: %w", region, err)
	}

	client := ssm.NewFromConfig(cfg)
	input := &ssm.DescribeInstanceInformationInput{
		Filters: []ssmtypes.InstanceInformationStringFilter{
			{
				Key:    aws.String("InstanceIds"),
				Values: []string{instanceID},
			},
		},
	}

	deadline := time.Now().Add(timeout)
	for {
		out, err := client.DescribeInstanceInformation(ctx, input)
		if err == nil {
			for _, info := range out.InstanceInformationList {
				if info.PingStatus == ssmtypes.PingStatusOnline {
					return nil
				}
			}
		}

		if time.Now().After(deadline) {
			if err != nil {
				return fmt.Errorf("timed out waiting for instance %s to register with SSM: %w", instanceID, err)
			}
			return fmt.Errorf("timed out waiting for instance %s to report SSM PingStatus Online", instanceID)
		}

		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(5 * time.Second):
		}
	}
}

// waitInstanceReady polls the instance's "knfsd-file-cache:status" tag until it
// reports "ready", or fails fast if it reports an "error:" status. The startup
// script sets this tag to "ready" only after its provisioning (e.g. installing
// nfs-common) completes. SSM PingStatus Online is reached far earlier in boot,
// so gating on the tag avoids racing the startup script (e.g. mounting NFS
// before the nfs-common mount helper is installed).
func waitInstanceReady(ctx context.Context, region, instanceID string, timeout time.Duration) error {
	cfg, err := config.LoadDefaultConfig(ctx, config.WithRegion(region))
	if err != nil {
		return fmt.Errorf("could not load AWS config for region %s: %w", region, err)
	}

	client := ec2.NewFromConfig(cfg)
	input := &ec2.DescribeTagsInput{
		Filters: []ec2types.Filter{
			{Name: aws.String("resource-id"), Values: []string{instanceID}},
			{Name: aws.String("key"), Values: []string{statusTagKey}},
		},
	}

	deadline := time.Now().Add(timeout)
	var lastStatus string
	for {
		out, err := client.DescribeTags(ctx, input)
		if err == nil {
			for _, tag := range out.Tags {
				lastStatus = aws.ToString(tag.Value)
				switch {
				case lastStatus == "ready":
					return nil
				case strings.HasPrefix(lastStatus, "error"):
					return fmt.Errorf("instance %s reported a failure status: %q", instanceID, lastStatus)
				}
			}
		}

		if time.Now().After(deadline) {
			if err != nil {
				return fmt.Errorf("timed out waiting for instance %s to report %s=ready: %w", instanceID, statusTagKey, err)
			}
			return fmt.Errorf("timed out waiting for instance %s to report %s=ready (last status: %q)", instanceID, statusTagKey, lastStatus)
		}

		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(5 * time.Second):
		}
	}
}
