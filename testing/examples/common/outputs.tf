/*
 * Copyright 2024 Google Inc.
 * Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 * SPDX-License-Identifier: Apache-2.0
 */

output "source" {
  description = "NFS source filer."
  value       = local.source
}

output "export_map" {
  description = "NFS source filer export map."
  value       = "${local.source};/files;/files"
}
