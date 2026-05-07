#!/usr/bin/env bash

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

set -eo pipefail

## set variables for build script only
BUILDARCH=$([ "$(uname -i)" = "aarch64" ] && echo "arm64" || echo "amd64")
HOSTNAME="knfsd-dev-ec2"
USERNAME="ubuntu"
VERSION="1.1.0-alpha.25"

## set env vars for build env only
export DEBIAN_FRONTEND=noninteractive
export DEBIAN_PRIORITY=critical

## root tasks
## disable unattended-upgrades.service
systemctl disable unattended-upgrades.service

## update amazon-ssm-agent
# wait up to 5 mins for snap seeding to complete before proceeding
if ! snap debug seeding | grep -q "^seeded: *true$"; then
	echo "Waiting for snap seeding to complete..."
	timeout 300 sh -c 'until snap debug seeding | grep -q "^seeded: *true$"; do sleep 5; done'
fi
snap stop amazon-ssm-agent
snap switch --channel=candidate amazon-ssm-agent
snap refresh amazon-ssm-agent
snap start amazon-ssm-agent

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
	&& echo "Defaults secure_path=\"/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin:/usr/local/go/bin:/home/${USERNAME}/go/bin:/home/${USERNAME}/.local/bin\"" >> /etc/sudoers.d/${USERNAME} \
	&& chmod 0440 /etc/sudoers.d/${USERNAME} \
	&& chmod 0444 /proc/slabinfo \
	&& ln -sf /usr/bin/python3 /usr/bin/python

## change permissions for docker
usermod -aG docker ${USERNAME}
setfacl --modify user:${USERNAME}:rw /var/run/docker.sock

## add extra env vars
# shellcheck disable=SC2031
echo "GITHUB_COM_TOKEN=" >> /etc/environment \
	&& echo "PACKER_GITHUB_API_TOKEN=" >> /etc/environment \
	&& echo "CI=devcontainer" >> /etc/environment \
	&& echo "DOCKER_CLI_HINTS=false" >> /etc/environment \
	&& echo "TF_APPEND_USER_AGENT=AWSSOLUTION/SO9129/${VERSION}" >> /etc/environment

## install aws-cli
curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-$(uname -i).zip" -o /tmp/awscliv2.zip \
	&& unzip -q -o /tmp/awscliv2.zip -d /tmp/aws-cli \
	&& bash /tmp/aws-cli/aws/install \
	&& rm -rf /tmp/awscliv2.zip /tmp/aws-cli

## build version args
# https://github.com/bats-core/bats-core/releases
KNFSD_BATS_CORE_VERSION=1.13.0
# https://github.com/psf/black/releases
KNFSD_BLACK_VERSION=26.3.1
# https://github.com/boto/boto3/tags
KNFSD_BOTO3_VERSION=1.43.5
# https://hub.docker.com/r/bridgecrew/checkov/tags
KNFSD_CHECKOV_VERSION=3.2.526
# https://github.com/codespell-project/codespell/releases
KNFSD_CODESPELL_VERSION=2.4.2
# https://github.com/editorconfig-checker/editorconfig-checker/releases
KNFSD_EDITORCONFIG_VERSION=3.6.1
# https://github.com/golangci/golangci-lint/releases
KNFSD_GOLANGCI_LINT_VERSION=2.12.2
# https://go.dev/dl/
KNFSD_GOLANG_VERSION=1.26.2
# https://github.com/securego/gosec/releases
KNFSD_GOSEC_VERSION=2.26.1
# https://github.com/python/mypy/tags
KNFSD_MYPY_VERSION=2.0.0
# https://github.com/hashicorp/packer/releases
KNFSD_PACKER_VERSION=1.15.3
# https://github.com/pre-commit/pre-commit/releases
KNFSD_PRECOMMIT_VERSION=4.6.0
# https://pypi.org/project/psycopg/
KNFSD_PSYCOPG_VERSION=3.3.4
# https://github.com/pylint-dev/pylint/tags
KNFSD_PYLINT_VERSION=4.0.5
# https://github.com/semgrep/semgrep/releases
KNFSD_SEMGREP_VERSION=1.161.0
# https://pypi.org/project/shellcheck-py/
KNFSD_SHELLCHECK_PY_VERSION=0.11.0.1
# https://github.com/mvdan/sh/releases
KNFSD_SHFMT_VERSION=3.13.1
# https://github.com/hashicorp/terraform/releases
KNFSD_TERRAFORM_VERSION=1.2.9
# https://github.com/gruntwork-io/terragrunt/releases
KNFSD_TERRAGRUNT_VERSION=1.0.3
# https://github.com/terraform-linters/tflint/releases
KNFSD_TFLINT_VERSION=0.62.0
# https://github.com/aquasecurity/trivy/releases
KNFSD_TRIVY_VERSION=0.70.0
# https://pypi.org/project/tzupdate/
KNFSD_TZUPDATE_VERSION=2.1.0
# https://github.com/astral-sh/uv/releases
KNFSD_UV_VERSION=0.11.11

## install golang, delete empty lines and lines containing PATH= in /etc/environment
curl -fsSL "https://dl.google.com/go/go${KNFSD_GOLANG_VERSION}.linux-${BUILDARCH}.tar.gz" -o "/tmp/go${KNFSD_GOLANG_VERSION}.linux-${BUILDARCH}.tar.gz" \
	&& tar -C /usr/local -xzf "/tmp/go${KNFSD_GOLANG_VERSION}.linux-${BUILDARCH}.tar.gz" \
	&& rm "/tmp/go${KNFSD_GOLANG_VERSION}.linux-${BUILDARCH}.tar.gz" \
	&& sed -i -e '/^PATH=/d' -e '/^$/d' /etc/environment \
	&& echo "PATH=$PATH:/usr/local/go/bin:/home/${USERNAME}/go/bin:/home/${USERNAME}/.local/bin" >> /etc/environment \
	&& source /etc/environment \
	&& export HOME="${HOME:-/root}" \
	&& go env -w GOPROXY=direct

## change current working directory
pushd /tmp > /dev/null

## install packer
curl -fsSL "https://releases.hashicorp.com/packer/${KNFSD_PACKER_VERSION}/packer_${KNFSD_PACKER_VERSION}_linux_${BUILDARCH}.zip" \
	--output packer.zip && unzip -q -o packer.zip -d /usr/local/bin && rm packer.zip

## install terraform
curl -fsSL "https://releases.hashicorp.com/terraform/${KNFSD_TERRAFORM_VERSION}/terraform_${KNFSD_TERRAFORM_VERSION}_linux_${BUILDARCH}.zip" \
	--output terraform.zip && unzip -q -o terraform.zip -d /usr/local/bin && rm terraform.zip

## install tflint
curl -fsSL "https://github.com/terraform-linters/tflint/releases/download/v${KNFSD_TFLINT_VERSION}/tflint_linux_${BUILDARCH}.zip" \
	--output tflint.zip && unzip -q -o tflint.zip -d /usr/local/bin && rm tflint.zip

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

## install editorconfig-checker
curl -fsSL "https://github.com/editorconfig-checker/editorconfig-checker/releases/download/v${KNFSD_EDITORCONFIG_VERSION}/ec-linux-${BUILDARCH}.tar.gz" \
	--output ec.tar.gz \
	&& sudo tar -xzf ec.tar.gz --strip-components=1 -C /usr/local/bin "bin/ec-linux-${BUILDARCH}" \
	&& sudo mv "/usr/local/bin/ec-linux-${BUILDARCH}" /usr/local/bin/editorconfig-checker \
	&& sudo chmod +x /usr/local/bin/editorconfig-checker && rm ec.tar.gz

## install shfmt
sudo curl -fsSL "https://github.com/mvdan/sh/releases/download/v${KNFSD_SHFMT_VERSION}/shfmt_v${KNFSD_SHFMT_VERSION}_linux_${BUILDARCH}" \
	--output /usr/local/bin/shfmt && sudo chmod +x /usr/local/bin/shfmt

## install gosec
curl -fsSL "https://github.com/securego/gosec/releases/download/v${KNFSD_GOSEC_VERSION}/gosec_${KNFSD_GOSEC_VERSION}_linux_${BUILDARCH}.tar.gz" \
	--output gosec.tar.gz && sudo tar -xzf gosec.tar.gz -C /usr/local/bin gosec \
	&& sudo chmod +x /usr/local/bin/gosec && rm gosec.tar.gz

## install uv
curl -fsSL "https://astral.sh/uv/${KNFSD_UV_VERSION}/install.sh" | sudo env UV_UNMANAGED_INSTALL="/usr/local/bin" sh

## run user-level tools as ${USERNAME}
sudo -Hiu "${USERNAME}" bash -l << EOT
set -eo pipefail

## add aliases, aws-cli completion, silence motd/sudo messages
{
	echo "alias cls='clear'"
	echo "alias tf='terraform'"
	echo "alias ec='editorconfig-checker'"
	echo "complete -C /usr/local/bin/aws_completer aws"
} >> ~/.bashrc
touch ~/.hushlogin

## configure GOPROXY=direct
go env -w GOPROXY=direct

## install golangci-lint
curl -sSfL "https://golangci-lint.run/install.sh" \
	| sh -s -- -b "/home/${USERNAME}/go/bin" v${KNFSD_GOLANGCI_LINT_VERSION}
mkdir -p ~/.cache/golangci-lint
echo 'export GOLANGCI_LINT_CACHE=\$HOME/.cache/golangci-lint' >> ~/.bashrc

## create pre-commit cache directory
mkdir -p ~/.cache/pre-commit
echo 'export PRE_COMMIT_HOME=\$HOME/.cache/pre-commit' >> ~/.bashrc

## create terraform plugin-cache directory
mkdir -p ~/.terraform.d/plugin-cache
echo 'export TF_PLUGIN_CACHE_DIR=\$HOME/.terraform.d/plugin-cache' >> ~/.bashrc

## create venv with uv
uv venv ~/.venv

## uv tool install binaries into isolated virt envs
uv tool install -q "tzupdate==${KNFSD_TZUPDATE_VERSION}" \
	&& uv tool install -q "black==${KNFSD_BLACK_VERSION}" \
	&& uv tool install -q "checkov==${KNFSD_CHECKOV_VERSION}" \
	&& uv tool install -q "codespell==${KNFSD_CODESPELL_VERSION}" \
	&& uv tool install -q "pre-commit==${KNFSD_PRECOMMIT_VERSION}" \
	&& uv tool install -q "shellcheck-py==${KNFSD_SHELLCHECK_PY_VERSION}" \
	&& uv tool install -q "semgrep==${KNFSD_SEMGREP_VERSION}"

## check versions available: see 'uv pip index versions PACKAGE'
uv pip install -q --python ~/.venv/bin/python \
	"boto3==${KNFSD_BOTO3_VERSION}" \
	"mypy==${KNFSD_MYPY_VERSION}" \
	"pylint==${KNFSD_PYLINT_VERSION}" \
	"psycopg==${KNFSD_PSYCOPG_VERSION}"

## create empty ~/.aws directory
mkdir -p ~/.aws
EOT

## final root tasks
## set timezone/date to local location
tzupdate

## create git repo dir, add safe.directory
mkdir -p /knfsd-file-cache && chown ${USERNAME}:${USERNAME} /knfsd-file-cache

## chown docker.sock
chown ${USERNAME}:${USERNAME} /var/run/docker.sock

## change ownership of everything in /home/${USERNAME}
chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}
