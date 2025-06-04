// Copyright 2023 Google LLC
// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: Apache-2.0

server "all-attributes" {
    url  = "https://10.0.0.2:8080"
    user = "nfs-proxy"

    password {
        aws_secret {
            region              = "eu-west-2"
            name                = "netapp-password"
            version             = "AWSCURRENT"
        }
    }
}

server "minimal" {
    url  = "https://10.0.0.2:8080"
    user = "nfs-proxy"

    password {
        aws_secret {
            name = "netapp-password"
        }
    }
}

server "previous-version" {
    url  = "https://10.0.0.2:8080"
    user = "nfs-proxy"

    password {
        aws_secret {
            name    = "netapp-password"
            version = "AWSPREVIOUS"
        }
    }
}

server "remote-secret" {
    url  = "https://10.0.0.2:8080"
    user = "nfs-proxy"

    password {
        aws_secret {
            region  = "us-east-1"
            name    = "password"
        }
    }
}
