// Copyright 2023 Google LLC
// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: Apache-2.0

server "basic-attributes" {
    url      = "https://10.0.0.2:8080"
    user     = "knfsd"
    password = file("./netapp-password")
}

server "tls" {
    url      = "https://10.0.0.2:8080"
    user     = "knfsd"
    password = "secret"

    tls {
        ca_certificate    = file("./netapp-ca.pem")
        allow_common_name = true
    }
}

server "empty-tls" {
    url      = "https://10.0.0.2:8080"
    user     = "knfsd"
    password = "secret"
    tls {}
}
