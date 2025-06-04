/*
  Copyright 2021 Google LLC
  Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
  SPDX-License-Identifier: Apache-2.0
 */

resource "google_monitoring_metric_descriptor" "fsid_request_count" {
  project      = var.PROJECT
  description  = "Number of requests received by the KNFSD FSID daemon."
  display_name = "knfsd-fsidd request count"
  type         = "knfsd/fsid/request/count"
  metric_kind  = "CUMULATIVE"
  value_type   = "INT64"
  unit         = "1"

  labels {
    key         = "command"
    description = "The command that was requested, such as \"get_fsid\"."
  }

  labels {
    key         = "result"
    description = "The result of the request, such as \"ok\"."
  }
}

resource "google_monitoring_metric_descriptor" "fsid_request_duration" {
  project      = var.PROJECT
  description  = "Total duration of requests received (including retries) by the KNFSD FSID daemon."
  display_name = "knfsd-fsidd request duration"
  type         = "knfsd/fsid/request/duration"
  metric_kind  = "CUMULATIVE"
  value_type   = "DISTRIBUTION"
  unit         = "ms"

  labels {
    key         = "command"
    description = "The command that was requested, such as \"get_fsid\"."
  }

  labels {
    key         = "result"
    description = "The result of the request, such as \"ok\"."
  }
}

resource "google_monitoring_metric_descriptor" "fsid_request_retries" {
  project      = var.PROJECT
  description  = "Number of times each request was retried."
  display_name = "knfsd fsidd request retries"
  type         = "knfsd/fsid/request/retries"
  metric_kind  = "CUMULATIVE"
  value_type   = "DISTRIBUTION"
  unit         = "{retries}"

  labels {
    key         = "command"
    description = "The command that was requested, such as \"get_fsid\"."
  }

  labels {
    key         = "result"
    description = "The result of the request, such as \"ok\"."
  }
}

resource "google_monitoring_metric_descriptor" "fsid_operation_count" {
  project      = var.PROJECT
  description  = "Number of operations performed by the KNFSD FSID daemon. Each attempt to handle a request is one operation."
  display_name = "knfsd-fsidd operation count"
  type         = "knfsd/fsid/operation/count"
  metric_kind  = "CUMULATIVE"
  value_type   = "INT64"
  unit         = "1"

  labels {
    key         = "command"
    description = "The command that was requested, such as \"get_fsid\"."
  }

  labels {
    key         = "result"
    description = "The result of the request, such as \"ok\"."
  }

  labels {
    key         = "retry"
    description = "The retry count for this operation."
  }
}

resource "google_monitoring_metric_descriptor" "fsid_operation_duration" {
  project      = var.PROJECT
  description  = "Duration of each operation performed by the KNFSD FSID daemon. Each attempt to handle a request is one operation."
  display_name = "knfsd-fsidd operation duration"
  type         = "knfsd/fsid/operation/duration"
  metric_kind  = "CUMULATIVE"
  value_type   = "DISTRIBUTION"
  unit         = "ms"

  labels {
    key         = "command"
    description = "The command that was requested, such as \"get_fsid\"."
  }

  labels {
    key         = "result"
    description = "The result of the request, such as \"ok\"."
  }

  labels {
    key         = "retry"
    description = "The retry count for this operation."
  }
}


resource "google_monitoring_metric_descriptor" "fsid_sql_query_count" {
  project      = var.PROJECT
  description  = "Number of SQL queries executed by the KNFSD FSID daemon."
  display_name = "knfsd-fsidd SQL query count"
  type         = "knfsd/fsid/sql/query/count"
  metric_kind  = "CUMULATIVE"
  value_type   = "INT64"
  unit         = "1"

  labels {
    key         = "query"
    description = "The query that was executed, such as \"get_fsid\"."
  }

  labels {
    key         = "result"
    description = "The result of the query, such as \"ok\"."
  }
}

resource "google_monitoring_metric_descriptor" "fsid_sql_query_duration" {
  project      = var.PROJECT
  description  = "Duration of SQL queries executed by the KNFSD FSID daemon."
  display_name = "knfsd-fsidd SQL query duration"
  type         = "knfsd/fsid/sql/query/duration"
  metric_kind  = "CUMULATIVE"
  value_type   = "DISTRIBUTION"
  unit         = "ms"

  labels {
    key         = "query"
    description = "The query that was executed, such as \"get_fsid\"."
  }

  labels {
    key         = "result"
    description = "The result of the query, such as \"ok\"."
  }
}
