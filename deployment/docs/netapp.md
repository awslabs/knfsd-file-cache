# NetApp Exports Auto-Discovery Configuration

For instructions on how to get the NetApp root CA certificate, and verify the `netapp-exports` command works, see the netapp-exports [README](../../image/resources/netapp-exports/README.md).

## NetApp Self-Signed Certificates

Modern SSL certificates use the Subject Alternate Name (SAN) field to provide a list of DNS names and IPs that are valid for the certificate.

However, older certificates relied on the Common Name (CN) field. This use has been deprecated and is no longer supported by default as the Common Name field was ambiguous.

If you have a certificate that does not contain a Subject Alternate Name then you can set `NETAPP_ALLOW_COMMON_NAME=true`. When this is enabled the Common Name *must* be the DNS name or IP address of the NetApp cluster. This DNS name or IP address *must* be used for the `NETAPP_URL` host.

If the certificate contains a Subject Alternate Name then the Common Name will be ignored.
