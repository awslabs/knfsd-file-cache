# Tests

This directory details the various tests that have been performed to evaluate various behaviors for the FAQ and when investigating issues.

These test plans document empirical testing of the KNFSD proxy cluster behavior under various failure scenarios and operational conditions. Each test follows a structured format:

* **Setup** - Environment configuration and prerequisites
* **Procedure** - Step-by-step test execution
* **Results** - Observed behavior during testing
* **Conclusion** - Summary of findings and recommendations

## Available Tests

* [Directory Listing](directory-listing.md) - Difference in caching of directory listings between proxy and source
* [Recovery: Source](recovery-source.md) - Client behavior when the source NFS server is unavailable
* [Recovery: Proxy](recovery-proxy.md) - Client behavior when the proxy cluster is unavailable
* [Recovery: Load Balancer](recovery-load-balancer.md) - Client behavior when the Network Load Balancer is unavailable
