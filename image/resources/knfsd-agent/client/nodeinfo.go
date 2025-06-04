/*
	Copyright 2022 Google LLC
	Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
	SPDX-License-Identifier: Apache-2.0
*/

package client

type NodeInfo struct {
	Name            string `json:"name"`
	InstanceID      string `json:"instanceId"`
	Hostname        string `json:"hostname"`
	InterfaceConfig struct {
		IPAddress        string `json:"ipAddress"`
		MACAddress       string `json:"macAddress"`
		PrivateIPs       string `json:"privateIps"`
		VPCID            string `json:"vpcId"`
		SubnetID         string `json:"subnetId"`
		SecurityGroups   string `json:"securityGroups"`
		SecurityGroupIDs string `json:"securityGroupIds"`
	} `json:"interfaceConfig"`
	Domain             string `json:"domain"`
	Partition          string `json:"partition"`
	Region             string `json:"region"`
	AvailabilityZone   string `json:"availabilityZone"`
	AvailabilityZoneID string `json:"availabilityZoneId"`
	InstanceType       string `json:"instanceType"`
	AmiID              string `json:"amiId"`
}

func (c *KnfsdAgentClient) NodeInfo() (*NodeInfo, error) {
	var v *NodeInfo
	err := c.get("api/v1/nodeInfo", &v)
	return v, err
}
