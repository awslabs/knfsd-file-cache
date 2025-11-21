module github.com/awslabs/knfsd-file-cache/image/resources/knfsd-metrics-agent

go 1.25.3

require (
	github.com/google/go-cmp v0.7.0
	github.com/open-telemetry/opentelemetry-collector-contrib/exporter/awsemfexporter v0.140.1
	github.com/open-telemetry/opentelemetry-collector-contrib/exporter/elasticsearchexporter v0.140.1
	github.com/open-telemetry/opentelemetry-collector-contrib/exporter/fileexporter v0.140.1
	github.com/open-telemetry/opentelemetry-collector-contrib/exporter/influxdbexporter v0.140.1
	github.com/open-telemetry/opentelemetry-collector-contrib/exporter/prometheusexporter v0.140.1
	github.com/open-telemetry/opentelemetry-collector-contrib/exporter/prometheusremotewriteexporter v0.140.1
	github.com/open-telemetry/opentelemetry-collector-contrib/processor/filterprocessor v0.140.1
	github.com/open-telemetry/opentelemetry-collector-contrib/processor/metricstransformprocessor v0.140.1
	github.com/open-telemetry/opentelemetry-collector-contrib/processor/resourcedetectionprocessor v0.140.1
	github.com/open-telemetry/opentelemetry-collector-contrib/processor/resourceprocessor v0.140.1
	github.com/open-telemetry/opentelemetry-collector-contrib/processor/transformprocessor v0.140.1
	github.com/prometheus/procfs v0.19.2
	github.com/stretchr/testify v1.11.1
	go.opentelemetry.io/collector/cmd/mdatagen v0.140.0
	go.opentelemetry.io/collector/component v1.46.0
	go.opentelemetry.io/collector/component/componenttest v0.140.0
	go.opentelemetry.io/collector/confmap v1.46.0
	go.opentelemetry.io/collector/confmap/provider/envprovider v1.46.0
	go.opentelemetry.io/collector/confmap/provider/fileprovider v1.46.0
	go.opentelemetry.io/collector/confmap/provider/yamlprovider v1.46.0
	go.opentelemetry.io/collector/consumer v1.46.0
	go.opentelemetry.io/collector/consumer/consumertest v0.140.0
	go.opentelemetry.io/collector/exporter/debugexporter v0.140.0
	go.opentelemetry.io/collector/exporter/otlpexporter v0.140.0
	go.opentelemetry.io/collector/exporter/otlphttpexporter v0.140.0
	go.opentelemetry.io/collector/extension/zpagesextension v0.140.0
	go.opentelemetry.io/collector/otelcol v0.140.0
	go.opentelemetry.io/collector/pdata v1.46.0
	go.opentelemetry.io/collector/processor/batchprocessor v0.140.0
	go.opentelemetry.io/collector/receiver v1.46.0
	go.opentelemetry.io/collector/receiver/otlpreceiver v0.140.0
	go.opentelemetry.io/collector/receiver/receivertest v0.140.0
	go.opentelemetry.io/collector/scraper v0.140.0
	go.opentelemetry.io/collector/scraper/scraperhelper v0.140.0
	go.opentelemetry.io/otel/metric v1.38.0
	go.opentelemetry.io/otel/trace v1.38.0
	go.uber.org/goleak v1.3.0
	go.uber.org/multierr v1.11.0
	go.uber.org/zap v1.27.1
	gopkg.in/yaml.v3 v3.0.1
)

require (
	cloud.google.com/go/auth v0.17.0 // indirect
	cloud.google.com/go/auth/oauth2adapt v0.2.8 // indirect
	cloud.google.com/go/compute/metadata v0.9.0 // indirect
	github.com/Azure/azure-sdk-for-go/sdk/azcore v1.20.0 // indirect
	github.com/Azure/azure-sdk-for-go/sdk/azidentity v1.13.1 // indirect
	github.com/Azure/azure-sdk-for-go/sdk/internal v1.11.2 // indirect
	github.com/AzureAD/microsoft-authentication-library-for-go v1.6.0 // indirect
	github.com/GoogleCloudPlatform/opentelemetry-operations-go/detectors/gcp v1.30.0 // indirect
	github.com/Microsoft/go-winio v0.6.2 // indirect
	github.com/Showmax/go-fqdn v1.0.0 // indirect
	github.com/alecthomas/participle/v2 v2.1.4 // indirect
	github.com/alecthomas/units v0.0.0-20240927000941-0f3dac36c52b // indirect
	github.com/antchfx/xmlquery v1.5.0 // indirect
	github.com/antchfx/xpath v1.3.5 // indirect
	github.com/armon/go-metrics v0.4.1 // indirect
	github.com/aws/aws-sdk-go-v2 v1.40.0 // indirect
	github.com/aws/aws-sdk-go-v2/aws/protocol/eventstream v1.7.3 // indirect
	github.com/aws/aws-sdk-go-v2/config v1.32.0 // indirect
	github.com/aws/aws-sdk-go-v2/credentials v1.19.0 // indirect
	github.com/aws/aws-sdk-go-v2/feature/ec2/imds v1.18.14 // indirect
	github.com/aws/aws-sdk-go-v2/internal/configsources v1.4.14 // indirect
	github.com/aws/aws-sdk-go-v2/internal/endpoints/v2 v2.7.14 // indirect
	github.com/aws/aws-sdk-go-v2/internal/ini v1.8.4 // indirect
	github.com/aws/aws-sdk-go-v2/service/cloudwatchlogs v1.60.1 // indirect
	github.com/aws/aws-sdk-go-v2/service/ec2 v1.272.1 // indirect
	github.com/aws/aws-sdk-go-v2/service/internal/accept-encoding v1.13.3 // indirect
	github.com/aws/aws-sdk-go-v2/service/internal/presigned-url v1.13.14 // indirect
	github.com/aws/aws-sdk-go-v2/service/signin v1.0.1 // indirect
	github.com/aws/aws-sdk-go-v2/service/sso v1.30.4 // indirect
	github.com/aws/aws-sdk-go-v2/service/ssooidc v1.35.8 // indirect
	github.com/aws/aws-sdk-go-v2/service/sts v1.41.1 // indirect
	github.com/aws/smithy-go v1.23.2 // indirect
	github.com/beorn7/perks v1.0.1 // indirect
	github.com/cenkalti/backoff/v5 v5.0.3 // indirect
	github.com/cespare/xxhash/v2 v2.3.0 // indirect
	github.com/cilium/ebpf v0.20.0 // indirect
	github.com/containerd/errdefs v1.0.0 // indirect
	github.com/containerd/errdefs/pkg v0.3.0 // indirect
	github.com/davecgh/go-spew v1.1.2-0.20180830191138-d8f796af33cc // indirect
	github.com/dennwc/varint v1.0.0 // indirect
	github.com/digitalocean/go-metadata v0.0.0-20250129100319-e3650a3df44b // indirect
	github.com/distribution/reference v0.6.0 // indirect
	github.com/docker/docker v28.5.2+incompatible // indirect
	github.com/docker/go-connections v0.6.0 // indirect
	github.com/docker/go-units v0.5.0 // indirect
	github.com/ebitengine/purego v0.9.1 // indirect
	github.com/elastic/elastic-transport-go/v8 v8.8.0 // indirect
	github.com/elastic/go-docappender/v2 v2.11.3 // indirect
	github.com/elastic/go-elasticsearch/v8 v8.19.0 // indirect
	github.com/elastic/go-freelru v0.16.0 // indirect
	github.com/elastic/go-grok v0.3.1 // indirect
	github.com/elastic/go-structform v0.0.12 // indirect
	github.com/elastic/lunes v0.2.0 // indirect
	github.com/emicklei/go-restful/v3 v3.13.0 // indirect
	github.com/expr-lang/expr v1.17.6 // indirect
	github.com/fatih/color v1.18.0 // indirect
	github.com/felixge/httpsnoop v1.0.4 // indirect
	github.com/foxboron/go-tpm-keyfiles v0.0.0-20250903184740-5d135037bd4d // indirect
	github.com/fsnotify/fsnotify v1.9.0 // indirect
	github.com/fxamacker/cbor/v2 v2.9.0 // indirect
	github.com/go-logr/logr v1.4.3 // indirect
	github.com/go-logr/stdr v1.2.2 // indirect
	github.com/go-ole/go-ole v1.3.0 // indirect
	github.com/go-openapi/jsonpointer v0.22.3 // indirect
	github.com/go-openapi/jsonreference v0.21.3 // indirect
	github.com/go-openapi/swag v0.25.3 // indirect
	github.com/go-openapi/swag/cmdutils v0.25.3 // indirect
	github.com/go-openapi/swag/conv v0.25.3 // indirect
	github.com/go-openapi/swag/fileutils v0.25.3 // indirect
	github.com/go-openapi/swag/jsonname v0.25.3 // indirect
	github.com/go-openapi/swag/jsonutils v0.25.3 // indirect
	github.com/go-openapi/swag/loading v0.25.3 // indirect
	github.com/go-openapi/swag/mangling v0.25.3 // indirect
	github.com/go-openapi/swag/netutils v0.25.3 // indirect
	github.com/go-openapi/swag/stringutils v0.25.3 // indirect
	github.com/go-openapi/swag/typeutils v0.25.3 // indirect
	github.com/go-openapi/swag/yamlutils v0.25.3 // indirect
	github.com/go-resty/resty/v2 v2.16.5 // indirect
	github.com/go-viper/mapstructure/v2 v2.4.0 // indirect
	github.com/gobwas/glob v0.2.3 // indirect
	github.com/goccy/go-json v0.10.5 // indirect
	github.com/gogo/protobuf v1.3.2 // indirect
	github.com/golang-jwt/jwt/v5 v5.3.0 // indirect
	github.com/golang/groupcache v0.0.0-20241129210726-2c02b8208cf8 // indirect
	github.com/golang/snappy v1.0.0 // indirect
	github.com/google/gnostic-models v0.7.1 // indirect
	github.com/google/go-tpm v0.9.7 // indirect
	github.com/google/s2a-go v0.1.9 // indirect
	github.com/google/uuid v1.6.0 // indirect
	github.com/googleapis/enterprise-certificate-proxy v0.3.7 // indirect
	github.com/googleapis/gax-go/v2 v2.15.0 // indirect
	github.com/grafana/regexp v0.0.0-20250905093917-f7b3be9d1853 // indirect
	github.com/grpc-ecosystem/grpc-gateway/v2 v2.27.3 // indirect
	github.com/hashicorp/consul/api v1.33.0 // indirect
	github.com/hashicorp/errwrap v1.1.0 // indirect
	github.com/hashicorp/go-cleanhttp v0.5.2 // indirect
	github.com/hashicorp/go-hclog v1.6.3 // indirect
	github.com/hashicorp/go-immutable-radix v1.3.1 // indirect
	github.com/hashicorp/go-metrics v0.5.4 // indirect
	github.com/hashicorp/go-multierror v1.1.1 // indirect
	github.com/hashicorp/go-rootcerts v1.0.2 // indirect
	github.com/hashicorp/go-version v1.7.0 // indirect
	github.com/hashicorp/golang-lru v1.0.2 // indirect
	github.com/hashicorp/golang-lru/v2 v2.0.7 // indirect
	github.com/hashicorp/serf v0.10.2 // indirect
	github.com/hetznercloud/hcloud-go/v2 v2.31.0 // indirect
	github.com/iancoleman/strcase v0.3.0 // indirect
	github.com/inconshreveable/mousetrap v1.1.0 // indirect
	github.com/influxdata/influxdb-observability/common v0.5.12 // indirect
	github.com/influxdata/influxdb-observability/otel2influx v0.5.12 // indirect
	github.com/influxdata/line-protocol/v2 v2.2.1 // indirect
	github.com/jpillora/backoff v1.0.0 // indirect
	github.com/json-iterator/go v1.1.12 // indirect
	github.com/klauspost/compress v1.18.1 // indirect
	github.com/klauspost/cpuid/v2 v2.3.0 // indirect
	github.com/knadh/koanf/maps v0.1.2 // indirect
	github.com/knadh/koanf/providers/confmap v1.0.0 // indirect
	github.com/knadh/koanf/v2 v2.3.0 // indirect
	github.com/kylelemons/godebug v1.1.0 // indirect
	github.com/lestrrat-go/strftime v1.1.1 // indirect
	github.com/lightstep/go-expohisto v1.0.0 // indirect
	github.com/linode/go-metadata v0.2.2 // indirect
	github.com/lufia/plan9stats v0.0.0-20251013123823-9fd1530e3ec3 // indirect
	github.com/magefile/mage v1.15.0 // indirect
	github.com/mattn/go-colorable v0.1.14 // indirect
	github.com/mattn/go-isatty v0.0.20 // indirect
	github.com/minio/sha256-simd v1.0.1 // indirect
	github.com/mitchellh/copystructure v1.2.0 // indirect
	github.com/mitchellh/go-homedir v1.1.0 // indirect
	github.com/mitchellh/reflectwalk v1.0.2 // indirect
	github.com/moby/docker-image-spec v1.3.1 // indirect
	github.com/modern-go/concurrent v0.0.0-20180306012644-bacd9c7ef1dd // indirect
	github.com/modern-go/reflect2 v1.0.3-0.20250322232337-35a7c28c31ee // indirect
	github.com/mostynb/go-grpc-compression v1.2.3 // indirect
	github.com/munnerz/goautoneg v0.0.0-20191010083416-a7dc8b61c822 // indirect
	github.com/mwitkow/go-conntrack v0.0.0-20190716064945-2f068394615f // indirect
	github.com/open-telemetry/opentelemetry-collector-contrib/internal/aws/awsutil v0.140.1 // indirect
	github.com/open-telemetry/opentelemetry-collector-contrib/internal/aws/cwlogs v0.140.1 // indirect
	github.com/open-telemetry/opentelemetry-collector-contrib/internal/aws/ecsutil v0.140.1 // indirect
	github.com/open-telemetry/opentelemetry-collector-contrib/internal/aws/metrics v0.140.1 // indirect
	github.com/open-telemetry/opentelemetry-collector-contrib/internal/common v0.140.1 // indirect
	github.com/open-telemetry/opentelemetry-collector-contrib/internal/coreinternal v0.140.1 // indirect
	github.com/open-telemetry/opentelemetry-collector-contrib/internal/filter v0.140.1 // indirect
	github.com/open-telemetry/opentelemetry-collector-contrib/internal/k8sconfig v0.140.1 // indirect
	github.com/open-telemetry/opentelemetry-collector-contrib/internal/metadataproviders v0.140.1 // indirect
	github.com/open-telemetry/opentelemetry-collector-contrib/internal/pdatautil v0.140.1 // indirect
	github.com/open-telemetry/opentelemetry-collector-contrib/internal/sharedcomponent v0.140.1 // indirect
	github.com/open-telemetry/opentelemetry-collector-contrib/pkg/ottl v0.140.1 // indirect
	github.com/open-telemetry/opentelemetry-collector-contrib/pkg/pdatautil v0.140.1 // indirect
	github.com/open-telemetry/opentelemetry-collector-contrib/pkg/resourcetotelemetry v0.140.1 // indirect
	github.com/open-telemetry/opentelemetry-collector-contrib/pkg/translator/prometheus v0.140.1 // indirect
	github.com/open-telemetry/opentelemetry-collector-contrib/pkg/translator/prometheusremotewrite v0.140.1 // indirect
	github.com/opencontainers/go-digest v1.0.0 // indirect
	github.com/opencontainers/image-spec v1.1.1 // indirect
	github.com/openshift/api v0.0.0-20251120040117-916c7003ed78 // indirect
	github.com/openshift/client-go v0.0.0-20251015124057-db0dee36e235 // indirect
	github.com/pierrec/lz4/v4 v4.1.22 // indirect
	github.com/pkg/browser v0.0.0-20240102092130-5ac0b6a4141c // indirect
	github.com/pkg/errors v0.9.1 // indirect
	github.com/pmezard/go-difflib v1.0.1-0.20181226105442-5d4384ee4fb2 // indirect
	github.com/power-devops/perfstat v0.0.0-20240221224432-82ca36839d55 // indirect
	github.com/prometheus/client_golang v1.23.2 // indirect
	github.com/prometheus/client_model v0.6.2 // indirect
	github.com/prometheus/common v0.67.3 // indirect
	github.com/prometheus/otlptranslator v1.0.0 // indirect
	github.com/prometheus/prometheus v0.307.3 // indirect
	github.com/prometheus/sigv4 v0.3.0 // indirect
	github.com/rs/cors v1.11.1 // indirect
	github.com/scaleway/scaleway-sdk-go v1.0.0-beta.35 // indirect
	github.com/shirou/gopsutil/v4 v4.25.10 // indirect
	github.com/spf13/cobra v1.10.1 // indirect
	github.com/spf13/pflag v1.0.10 // indirect
	github.com/stretchr/objx v0.5.3 // indirect
	github.com/tidwall/gjson v1.18.0 // indirect
	github.com/tidwall/match v1.2.0 // indirect
	github.com/tidwall/pretty v1.2.1 // indirect
	github.com/tidwall/tinylru v1.2.1 // indirect
	github.com/tidwall/wal v1.2.1 // indirect
	github.com/tklauser/go-sysconf v0.3.16 // indirect
	github.com/tklauser/numcpus v0.11.0 // indirect
	github.com/twmb/murmur3 v1.1.8 // indirect
	github.com/ua-parser/uap-go v0.0.0-20250917011043-9c86a9b0f8f0 // indirect
	github.com/x448/float16 v0.8.4 // indirect
	github.com/yusufpapurcu/wmi v1.2.4 // indirect
	github.com/zeebo/xxh3 v1.0.2 // indirect
	go.elastic.co/fastjson v1.5.1 // indirect
	go.opentelemetry.io/auto/sdk v1.2.1 // indirect
	go.opentelemetry.io/collector v0.140.0 // indirect
	go.opentelemetry.io/collector/client v1.46.0 // indirect
	go.opentelemetry.io/collector/component/componentstatus v0.140.0 // indirect
	go.opentelemetry.io/collector/config/configauth v1.46.0 // indirect
	go.opentelemetry.io/collector/config/configcompression v1.46.0 // indirect
	go.opentelemetry.io/collector/config/configgrpc v0.140.0 // indirect
	go.opentelemetry.io/collector/config/confighttp v0.140.0 // indirect
	go.opentelemetry.io/collector/config/configmiddleware v1.46.0 // indirect
	go.opentelemetry.io/collector/config/confignet v1.46.0 // indirect
	go.opentelemetry.io/collector/config/configopaque v1.46.0 // indirect
	go.opentelemetry.io/collector/config/configoptional v1.46.0 // indirect
	go.opentelemetry.io/collector/config/configretry v1.46.0 // indirect
	go.opentelemetry.io/collector/config/configtelemetry v0.140.0 // indirect
	go.opentelemetry.io/collector/config/configtls v1.46.0 // indirect
	go.opentelemetry.io/collector/confmap/xconfmap v0.140.0 // indirect
	go.opentelemetry.io/collector/connector v0.140.0 // indirect
	go.opentelemetry.io/collector/connector/connectortest v0.140.0 // indirect
	go.opentelemetry.io/collector/connector/xconnector v0.140.0 // indirect
	go.opentelemetry.io/collector/consumer/consumererror v0.140.0 // indirect
	go.opentelemetry.io/collector/consumer/consumererror/xconsumererror v0.140.0 // indirect
	go.opentelemetry.io/collector/consumer/xconsumer v0.140.0 // indirect
	go.opentelemetry.io/collector/exporter v1.46.0 // indirect
	go.opentelemetry.io/collector/exporter/exporterhelper v0.140.0 // indirect
	go.opentelemetry.io/collector/exporter/exporterhelper/xexporterhelper v0.140.0 // indirect
	go.opentelemetry.io/collector/exporter/exportertest v0.140.0 // indirect
	go.opentelemetry.io/collector/exporter/xexporter v0.140.0 // indirect
	go.opentelemetry.io/collector/extension v1.46.0 // indirect
	go.opentelemetry.io/collector/extension/extensionauth v1.46.0 // indirect
	go.opentelemetry.io/collector/extension/extensioncapabilities v0.140.0 // indirect
	go.opentelemetry.io/collector/extension/extensionmiddleware v0.140.0 // indirect
	go.opentelemetry.io/collector/extension/extensiontest v0.140.0 // indirect
	go.opentelemetry.io/collector/extension/xextension v0.140.0 // indirect
	go.opentelemetry.io/collector/featuregate v1.46.0 // indirect
	go.opentelemetry.io/collector/filter v0.140.0 // indirect
	go.opentelemetry.io/collector/internal/fanoutconsumer v0.140.0 // indirect
	go.opentelemetry.io/collector/internal/sharedcomponent v0.140.0 // indirect
	go.opentelemetry.io/collector/internal/telemetry v0.140.0 // indirect
	go.opentelemetry.io/collector/pdata/pprofile v0.140.0 // indirect
	go.opentelemetry.io/collector/pdata/testdata v0.140.0 // indirect
	go.opentelemetry.io/collector/pdata/xpdata v0.140.0 // indirect
	go.opentelemetry.io/collector/pipeline v1.46.0 // indirect
	go.opentelemetry.io/collector/pipeline/xpipeline v0.140.0 // indirect
	go.opentelemetry.io/collector/processor v1.46.0 // indirect
	go.opentelemetry.io/collector/processor/processorhelper v0.140.0 // indirect
	go.opentelemetry.io/collector/processor/processorhelper/xprocessorhelper v0.140.0 // indirect
	go.opentelemetry.io/collector/processor/processortest v0.140.0 // indirect
	go.opentelemetry.io/collector/processor/xprocessor v0.140.0 // indirect
	go.opentelemetry.io/collector/receiver/receiverhelper v0.140.0 // indirect
	go.opentelemetry.io/collector/receiver/xreceiver v0.140.0 // indirect
	go.opentelemetry.io/collector/semconv v0.128.1-0.20250610090210-188191247685 // indirect
	go.opentelemetry.io/collector/service v0.140.0 // indirect
	go.opentelemetry.io/collector/service/hostcapabilities v0.140.0 // indirect
	go.opentelemetry.io/contrib/bridges/otelzap v0.13.0 // indirect
	go.opentelemetry.io/contrib/instrumentation/google.golang.org/grpc/otelgrpc v0.63.0 // indirect
	go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp v0.63.0 // indirect
	go.opentelemetry.io/contrib/otelconf v0.18.0 // indirect
	go.opentelemetry.io/contrib/propagators/b3 v1.38.0 // indirect
	go.opentelemetry.io/contrib/zpages v0.63.0 // indirect
	go.opentelemetry.io/ebpf-profiler v0.0.202547 // indirect
	go.opentelemetry.io/otel v1.38.0 // indirect
	go.opentelemetry.io/otel/exporters/otlp/otlplog/otlploggrpc v0.14.0 // indirect
	go.opentelemetry.io/otel/exporters/otlp/otlplog/otlploghttp v0.14.0 // indirect
	go.opentelemetry.io/otel/exporters/otlp/otlpmetric/otlpmetricgrpc v1.38.0 // indirect
	go.opentelemetry.io/otel/exporters/otlp/otlpmetric/otlpmetrichttp v1.38.0 // indirect
	go.opentelemetry.io/otel/exporters/otlp/otlptrace v1.38.0 // indirect
	go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc v1.38.0 // indirect
	go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp v1.38.0 // indirect
	go.opentelemetry.io/otel/exporters/prometheus v0.60.0 // indirect
	go.opentelemetry.io/otel/exporters/stdout/stdoutlog v0.14.0 // indirect
	go.opentelemetry.io/otel/exporters/stdout/stdoutmetric v1.38.0 // indirect
	go.opentelemetry.io/otel/exporters/stdout/stdouttrace v1.38.0 // indirect
	go.opentelemetry.io/otel/log v0.14.0 // indirect
	go.opentelemetry.io/otel/sdk v1.38.0 // indirect
	go.opentelemetry.io/otel/sdk/log v0.14.0 // indirect
	go.opentelemetry.io/otel/sdk/metric v1.38.0 // indirect
	go.opentelemetry.io/proto/otlp v1.9.0 // indirect
	go.uber.org/atomic v1.11.0 // indirect
	go.yaml.in/yaml/v2 v2.4.3 // indirect
	go.yaml.in/yaml/v3 v3.0.4 // indirect
	golang.org/x/crypto v0.45.0 // indirect
	golang.org/x/exp v0.0.0-20251113190631-e25ba8c21ef6 // indirect
	golang.org/x/net v0.47.0 // indirect
	golang.org/x/oauth2 v0.33.0 // indirect
	golang.org/x/sync v0.18.0 // indirect
	golang.org/x/sys v0.38.0 // indirect
	golang.org/x/term v0.37.0 // indirect
	golang.org/x/text v0.31.0 // indirect
	golang.org/x/time v0.14.0 // indirect
	gonum.org/v1/gonum v0.16.0 // indirect
	google.golang.org/api v0.256.0 // indirect
	google.golang.org/genproto/googleapis/api v0.0.0-20251111163417-95abcf5c77ba // indirect
	google.golang.org/genproto/googleapis/rpc v0.0.0-20251111163417-95abcf5c77ba // indirect
	google.golang.org/grpc v1.77.0 // indirect
	google.golang.org/protobuf v1.36.10 // indirect
	gopkg.in/evanphx/json-patch.v4 v4.13.0 // indirect
	gopkg.in/inf.v0 v0.9.1 // indirect
	gopkg.in/natefinch/lumberjack.v2 v2.2.1 // indirect
	gopkg.in/yaml.v2 v2.4.0 // indirect
	k8s.io/api v0.34.2 // indirect
	k8s.io/apimachinery v0.34.2 // indirect
	k8s.io/client-go v0.34.2 // indirect
	k8s.io/klog/v2 v2.130.1 // indirect
	k8s.io/kube-openapi v0.0.0-20250910181357-589584f1c912 // indirect
	k8s.io/utils v0.0.0-20251002143259-bc988d571ff4 // indirect
	sigs.k8s.io/json v0.0.0-20250730193827-2d320260d730 // indirect
	sigs.k8s.io/randfill v1.0.0 // indirect
	sigs.k8s.io/structured-merge-diff/v6 v6.3.0 // indirect
	sigs.k8s.io/yaml v1.6.0 // indirect
)
