#!/usr/bin/env bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

set -eo pipefail

## set variables for build script only
BUILDARCH=$([ "$(uname -i)" = "aarch64" ] && echo "arm64" || echo "amd64")
HOSTNAME="knfsd-dev-ec2"
USERNAME="ubuntu"
VERSION="1.1.0-alpha.13"

## set env vars for build env only
export HOME=/home/${USERNAME}
export DEBIAN_FRONTEND=noninteractive
export DEBIAN_PRIORITY=critical

## OS update, upgrade, install apt pkgs
apt-get -y -q update && apt-get -y -q upgrade \
	&& apt-get -y -q install -o=Dpkg::Use-Pty=0 \
		acl \
		apt-utils \
		bash-completion \
		build-essential \
		ca-certificates \
		curl \
		dnsutils \
		dpkg \
		file \
		gcc \
		git \
		gnupg \
		htop \
		iputils-ping \
		jq \
		less \
		locales \
		make \
		man \
		man-db \
		nfstrace \
		openssh-client \
		python3-pip \
		python3-venv \
		rsync \
		sudo \
		tar \
		traceroute \
		tzdata \
		unzip \
		vim

## configure en_US.UTF-8 locale
echo 'en_US.UTF-8 UTF-8' >> /etc/locale.gen && locale-gen \
	&& update-locale LC_ALL=C.UTF-8 LANG=en_US.UTF-8

## change hostname, add HOSTNAME to /etc/hosts
hostnamectl set-hostname ${HOSTNAME}
sed -i "/127\.0\.0\.1 localhost/a 127.0.0.1 ${HOSTNAME}" /etc/hosts

## setup docker apt repo
install -m 0755 -d /etc/apt/keyrings \
	&& curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc \
	&& chmod a+r /etc/apt/keyrings/docker.asc \
	&& echo \
		"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
		$(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

## install docker & cleanup apt pkgs
apt-get -y -q update && apt-get -y -q install \
	containerd.io \
	docker-buildx-plugin \
	docker-ce \
	docker-ce-cli \
	docker-compose-plugin \
	&& apt-get clean \
	&& rm -rf /var/lib/apt/lists/*

## configure default logging driver for docker
mkdir -p /etc/docker \
	&& jq -n '{"log-driver": "json-file", "log-opts": {"max-size": "10m", "max-file": "5"}}' >> /etc/docker/daemon.json

## install latest postgressql-client
echo "deb http://apt.postgresql.org/pub/repos/apt $(. /etc/os-release && echo "$VERSION_CODENAME")-pgdg main" >> /etc/apt/sources.list.d/pgdg.list \
	&& curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /etc/apt/trusted.gpg.d/postgresql.gpg \
	&& apt-get -y -q update \
	&& apt-get -y -q install postgresql-client \
	&& apt-get clean \
	&& rm -rf /var/lib/apt/lists/*

## silence sudo usage message, grant sudo rights, allow read access to /proc/slabinfo (knfsd-metrics-agent go tests), symlink python3
echo "Defaults !admin_flag" >> /etc/sudoers.d/disable_admin_file \
	&& rm -f /etc/sudoers.d/90-cloud-init-users \
	&& chmod 0440 /etc/sudoers.d/disable_admin_file \
	&& echo ${USERNAME} ALL=\(root\) NOPASSWD:ALL >> /etc/sudoers.d/${USERNAME} \
	&& echo 'Defaults secure_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin:/usr/local/go/bin:/home/ubuntu/go/bin"' >> /etc/sudoers.d/${USERNAME} \
	&& chmod 0440 /etc/sudoers.d/${USERNAME} \
	&& chmod 0444 /proc/slabinfo \
	&& ln -sf /usr/bin/python3 /usr/bin/python

## change permissions for docker
usermod -aG docker ${USERNAME}
setfacl --modify user:${USERNAME}:rw /var/run/docker.sock

## add aliases, extra env vars, silence motd/sudo messages
# shellcheck disable=SC2031
echo "alias cls='clear'" >> /home/${USERNAME}/.bashrc \
	&& echo "alias tf='terraform'" >> /home/${USERNAME}/.bashrc \
	&& echo "alias ec='editorconfig-checker'" >> /home/${USERNAME}/.bashrc \
	&& touch "/home/${USERNAME}/.hushlogin" \
	&& echo "GITHUB_COM_TOKEN=" >> /etc/environment \
	&& echo "PACKER_GITHUB_API_TOKEN=" >> /etc/environment \
	&& echo "CI=devcontainer" >> /etc/environment \
	&& echo "DOCKER_CLI_HINTS=false" >> /etc/environment \
	&& echo "TF_APPEND_USER_AGENT=AWSSOLUTION/SO9129/${VERSION}" >> /etc/environment

## install aws-cli
curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-$(uname -i).zip" -o /tmp/awscliv2.zip \
	&& unzip -q -o /tmp/awscliv2.zip -d /tmp/aws-cli \
	&& bash /tmp/aws-cli/aws/install \
	&& rm -rf /tmp/awscliv2.zip /tmp/aws-cli \
	&& echo 'complete -C "/usr/local/bin/aws_completer" aws' >> /home/${USERNAME}/.bashrc

## build version args
# https://github.com/bats-core/bats-core/releases
KNFSD_BATS_CORE_VERSION=1.12.0
# https://github.com/psf/black/releases
KNFSD_BLACK_VERSION=25.9.0
# https://github.com/boto/boto3/tags
KNFSD_BOTO3_VERSION=1.40.59
# https://hub.docker.com/r/bridgecrew/checkov/tags
KNFSD_CHECKOV_VERSION=3.2.488
# https://github.com/codespell-project/codespell/releases
KNFSD_CODESPELL_VERSION=2.4.1
# https://github.com/editorconfig-checker/editorconfig-checker/releases
KNFSD_EDITORCONFIG_VERSION=3.4.1
# https://github.com/golangci/golangci-lint/releases
KNFSD_GOLANGCI_LINT_VERSION=2.5.0
# https://go.dev/dl/
KNFSD_GOLANG_VERSION=1.25.3
# https://github.com/python/mypy/tags
KNFSD_MYPY_VERSION=1.18.2
# https://github.com/hashicorp/packer/releases
KNFSD_PACKER_VERSION=1.14.2
# https://github.com/pre-commit/pre-commit/releases
KNFSD_PRECOMMIT_VERSION=4.3.0
# https://pypi.org/project/psycopg/
KNFSD_PSYCOPG_VERSION=3.2.12
# https://github.com/pylint-dev/pylint/tags
KNFSD_PYLINT_VERSION=4.0.2
# https://github.com/semgrep/semgrep/releases
KNFSD_SEMGREP_VERSION=1.141.0
# https://pypi.org/project/shellcheck-py/
KNFSD_SHELLCHECK_PY_VERSION=0.11.0.1
# https://github.com/mvdan/sh/releases
KNFSD_SHFMT_VERSION=3.12.0
# https://github.com/hashicorp/terraform/releases
KNFSD_TERRAFORM_VERSION=1.2.9
# https://github.com/gruntwork-io/terragrunt/releases
KNFSD_TERRAGRUNT_VERSION=0.91.5
# https://github.com/terraform-linters/tflint/releases
KNFSD_TFLINT_VERSION=0.59.1
# https://github.com/aquasecurity/tfsec/releases
KNFSD_TFSEC_VERSION=1.28.14
# https://github.com/aquasecurity/trivy/releases
KNFSD_TRIVY_VERSION=0.67.2

## install golang, delete empty lines and lines containing PATH= in /etc/environment
curl -fsSL "https://dl.google.com/go/go${KNFSD_GOLANG_VERSION}.linux-${BUILDARCH}.tar.gz" -o "/tmp/go${KNFSD_GOLANG_VERSION}.linux-${BUILDARCH}.tar.gz" \
	&& tar -C /usr/local -xzf "/tmp/go${KNFSD_GOLANG_VERSION}.linux-${BUILDARCH}.tar.gz" \
	&& rm "/tmp/go${KNFSD_GOLANG_VERSION}.linux-${BUILDARCH}.tar.gz" \
	&& sed -i -e '/^PATH=/d' -e '/^$/d' /etc/environment \
	&& echo "PATH=$PATH:/usr/local/go/bin:/home/${USERNAME}/go/bin" >> /etc/environment \
	&& source /etc/environment && go env -w GOPROXY=direct \
	&& sudo go env -w GOPROXY=direct

## install golangci-lint
curl -sSfL "https://raw.githubusercontent.com/golangci/golangci-lint/master/install.sh" \
	| sh -s -- -b "$(go env GOPATH)/bin" v${KNFSD_GOLANGCI_LINT_VERSION} \
	&& mkdir -p "/home/${USERNAME}/.cache/golangci-lint" \
	&& echo 'export GOLANGCI_LINT_CACHE=$HOME/.cache/golangci-lint' >> /home/${USERNAME}/.bashrc

## install golang tools
go install mvdan.cc/sh/v3/cmd/shfmt@v${KNFSD_SHFMT_VERSION}
go install github.com/editorconfig-checker/editorconfig-checker/v3/cmd/editorconfig-checker@v${KNFSD_EDITORCONFIG_VERSION}

## create pre-commit cache directory
mkdir -p "/home/${USERNAME}/.cache/pre-commit" \
	&& echo 'export PRE_COMMIT_HOME=$HOME/.cache/pre-commit' >> /home/${USERNAME}/.bashrc

## change current working directory
pushd /tmp > /dev/null

## install packer
curl -fsSL "https://releases.hashicorp.com/packer/${KNFSD_PACKER_VERSION}/packer_${KNFSD_PACKER_VERSION}_linux_${BUILDARCH}.zip" \
	--output packer.zip && unzip -q -o packer.zip -d /usr/local/bin && rm packer.zip

## install terraform
curl -fsSL "https://releases.hashicorp.com/terraform/${KNFSD_TERRAFORM_VERSION}/terraform_${KNFSD_TERRAFORM_VERSION}_linux_${BUILDARCH}.zip" \
	--output terraform.zip && unzip -q -o terraform.zip -d /usr/local/bin && rm terraform.zip
mkdir -p "/home/${USERNAME}/.terraform.d/plugin-cache" \
	&& echo 'export TF_PLUGIN_CACHE_DIR=$HOME/.terraform.d/plugin-cache' >> /home/${USERNAME}/.bashrc

## install tflint
curl -fsSL "https://github.com/terraform-linters/tflint/releases/download/v${KNFSD_TFLINT_VERSION}/tflint_linux_${BUILDARCH}.zip" \
	--output tflint.zip && unzip -q -o tflint.zip -d /usr/local/bin && rm tflint.zip

## install tfsec
curl -fsSL "https://github.com/aquasecurity/tfsec/releases/download/v${KNFSD_TFSEC_VERSION}/tfsec_${KNFSD_TFSEC_VERSION}_linux_${BUILDARCH}.tar.gz" \
	--output tfsec.tar.gz && tar -xf tfsec.tar.gz tfsec && rm tfsec.tar.gz && install tfsec /usr/local/bin && rm -rf tfsec

## install trivy
ARCH=$([ "${BUILDARCH}" = "arm64" ] && echo "ARM64" || echo "64bit")
curl -fsSL "https://github.com/aquasecurity/trivy/releases/download/v${KNFSD_TRIVY_VERSION}/trivy_${KNFSD_TRIVY_VERSION}_Linux-${ARCH}.deb" \
	--output trivy.deb && sudo dpkg -i trivy.deb && rm trivy.deb

## install bats-core
curl -fsSL "https://github.com/bats-core/bats-core/archive/refs/tags/v${KNFSD_BATS_CORE_VERSION}.zip" \
	--output bats-core.zip && unzip -q -o bats-core.zip && ./bats-core-${KNFSD_BATS_CORE_VERSION}/install.sh /usr/local \
	&& rm -rf bats-core.zip bats-core-${KNFSD_BATS_CORE_VERSION}

## install terragrunt
curl -fsSL "https://github.com/gruntwork-io/terragrunt/releases/download/v${KNFSD_TERRAGRUNT_VERSION}/terragrunt_linux_${BUILDARCH}" \
	--output /usr/local/bin/terragrunt && chmod +x /usr/local/bin/terragrunt

## create venv, activate, install/upgrade pip/pipx, ensure path global
python3 -m venv /home/${USERNAME}/.venv
"/home/${USERNAME}/.venv/bin/pip" install -qq --upgrade pip pipx
"/home/${USERNAME}/.venv/bin/pipx" ensurepath -qq --global

## pipx install system-wide binaries into isolated virt envs
"/home/${USERNAME}/.venv/bin/pipx" install -qq --global \
	"tzupdate" \
	"black==${KNFSD_BLACK_VERSION}" \
	"checkov==${KNFSD_CHECKOV_VERSION}" \
	"codespell==${KNFSD_CODESPELL_VERSION}" \
	"pre-commit==${KNFSD_PRECOMMIT_VERSION}" \
	"shellcheck-py==${KNFSD_SHELLCHECK_PY_VERSION}" \
	"semgrep==${KNFSD_SEMGREP_VERSION}"

## check versions available: $ pip index versions <package-name>
"/home/${USERNAME}/.venv/bin/pip" install -qq --break-system-packages \
	"boto3==${KNFSD_BOTO3_VERSION}" \
	"mypy==${KNFSD_MYPY_VERSION}" \
	"pylint==${KNFSD_PYLINT_VERSION}" \
	"psycopg==${KNFSD_PSYCOPG_VERSION}"

## set timezone/date to local location
tzupdate

## create git repo dir, add safe.directory
mkdir -p /knfsd-file-cache && chown ${USERNAME}:${USERNAME} /knfsd-file-cache

## create empty ~/.aws directory
mkdir -p /home/${USERNAME}/.aws

## chown docker.sock
chown ${USERNAME}:${USERNAME} /var/run/docker.sock

## change ownership of everything in $HOME
chown -R ${USERNAME}:${USERNAME} $HOME
