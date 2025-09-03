# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

## docker build --tag knfsd-dev:latest --file .devcontainer/dev/Dockerfile .
## docker run --platform linux/amd64 --rm --name knfsd-dev --hostname knfsd-dev -it -v /var/run/docker.sock:/var/run/docker.sock knfsd-dev

FROM --platform=${BUILDPLATFORM} public.ecr.aws/lts/ubuntu:24.04

ARG VERSION="1.1.0-alpha.8"

LABEL org.opencontainers.image.source="https://github.com/awslabs/knfsd-file-cache"
LABEL org.opencontainers.image.description="knfsd-file-cache development container image"
LABEL org.opencontainers.image.authors="knfsd-file-cache@amazon.com"
LABEL org.opencontainers.image.vendor="Amazon Web Services"
LABEL org.opencontainers.image.licenses="Apache-2.0"
LABEL org.opencontainers.image.version=${VERSION}

HEALTHCHECK NONE

## set default SHELL to bash
SHELL ["/bin/bash", "-c"]

WORKDIR /

## set devcontainer env vars
ENV CI=devcontainer
ENV DOCKER_CLI_HINTS=false
ENV TF_APPEND_USER_AGENT="AWSSOLUTION/SO9129/${VERSION}"

## set devcontainer build args
ARG BUILDARCH
ARG DEBIAN_FRONTEND=noninteractive
ARG DEBIAN_PRIORITY=critical

## OS update, upgrade, install & cleanup apt pkgs
## Ubuntu 24.04 onwards, unminimize is a package, install, then RUN
RUN set -eux \
    && apt-get -y -q update && apt-get -y -q upgrade \
    && apt-get -y -q install -o=Dpkg::Use-Pty=0 \
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
    unminimize \
    unzip \
    vim \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

## unminimize the image
RUN yes | unminimize

## configure en_US.UTF-8 locale
RUN echo 'en_US.UTF-8 UTF-8' >> /etc/locale.gen && locale-gen \
    && update-locale LC_ALL=C.UTF-8 LANG=en_US.UTF-8

## setup docker apt repo
RUN set -eux \
    && install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc \
    && chmod a+r /etc/apt/keyrings/docker.asc \
    && echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
        $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

## install docker & cleanup apt pkgs
RUN set -eux \
    && apt-get -y -q update && apt-get -y -q install \
    containerd.io \
    docker-buildx-plugin \
    docker-ce \
    docker-ce-cli \
    docker-compose-plugin \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

## configure default logging driver for docker
RUN mkdir -p /etc/docker \
    && jq -n '{"log-driver": "json-file", "log-opts": {"max-size": "10m", "max-file": "5"}}' >> /etc/docker/daemon.json

## install latest postgressql-client
RUN set -eux \
    && echo "deb http://apt.postgresql.org/pub/repos/apt $(. /etc/os-release && echo "$VERSION_CODENAME")-pgdg main" >> /etc/apt/sources.list.d/pgdg.list \
    && curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /etc/apt/trusted.gpg.d/postgresql.gpg \
    && apt-get -y -q update \
    && apt-get -y -q install postgresql-client \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

## non-root user
ARG USERNAME=ubuntu

## silence sudo usage message, grant sudo rights, symlink python3
RUN set -eux \
    && echo "Defaults !admin_flag" >> /etc/sudoers.d/disable_admin_file \
    && chmod 0440 /etc/sudoers.d/disable_admin_file \
    && echo ${USERNAME} ALL=\(root\) NOPASSWD:ALL >> /etc/sudoers.d/${USERNAME} \
    && echo 'Defaults secure_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin:/usr/local/go/bin:/home/ubuntu/go/bin"' >> /etc/sudoers.d/${USERNAME} \
    && chmod 0440 /etc/sudoers.d/${USERNAME} \
    && ln -sf /usr/bin/python3 /usr/bin/python

## change permissions for docker
RUN usermod -aG docker ${USERNAME}

## run container as non-root user
USER ${USERNAME}

## persist bash history in container, add aliases, silence motd/sudo messages
RUN SNIPPET="export PROMPT_COMMAND='history -a' && export HISTFILE=/home/${USERNAME}/.commandhistory/.bash_history" \
    && mkdir -p "/home/${USERNAME}/.commandhistory" && touch "/home/${USERNAME}/.commandhistory/.bash_history" \
    && echo "${SNIPPET}" >> /home/${USERNAME}/.bashrc \
    && echo "alias cls='clear'" >> /home/${USERNAME}/.bashrc \
    && echo "alias tf='terraform'" >> /home/${USERNAME}/.bashrc \
    && echo "alias ec='editorconfig-checker'" >> /home/${USERNAME}/.bashrc \
    && touch "/home/${USERNAME}/.hushlogin"

## install aws-cli
RUN set -eux \
    && ARCH=$([ "${BUILDARCH}" = "arm64" ] && echo "aarch64" || echo "x86_64") \
    && curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${ARCH}.zip" -o /tmp/awscliv2.zip \
    && unzip -q -o /tmp/awscliv2.zip -d /tmp/aws-cli \
    && sudo bash /tmp/aws-cli/aws/install \
    && rm -rf /tmp/awscliv2.zip /tmp/aws-cli \
    && echo 'complete -C "/usr/local/bin/aws_completer" aws' >> /home/${USERNAME}/.bashrc

## build version args
# https://github.com/bats-core/bats-core/releases
ARG KNFSD_BATS_CORE_VERSION=1.12.0
# https://github.com/psf/black/releases
ARG KNFSD_BLACK_VERSION=25.1.0
# https://github.com/boto/boto3/tags
ARG KNFSD_BOTO3_VERSION=1.40.21
# https://hub.docker.com/r/bridgecrew/checkov/tags
ARG KNFSD_CHECKOV_VERSION=3.2.469
# https://github.com/codespell-project/codespell/releases
ARG KNFSD_CODESPELL_VERSION=2.4.1
# https://github.com/editorconfig-checker/editorconfig-checker/releases
ARG KNFSD_EDITORCONFIG_VERSION=3.4.0
# https://github.com/golangci/golangci-lint/releases
ARG KNFSD_GOLANGCI_LINT_VERSION=2.4.0
# https://go.dev/dl/
ARG KNFSD_GOLANG_VERSION=1.25.0
# https://github.com/python/mypy/tags
ARG KNFSD_MYPY_VERSION=1.17.1
# https://github.com/hashicorp/packer/releases
ARG KNFSD_PACKER_VERSION=1.14.1
# https://github.com/pre-commit/pre-commit/releases
ARG KNFSD_PRECOMMIT_VERSION=4.3.0
# https://pypi.org/project/psycopg/
ARG KNFSD_PSYCOPG_VERSION=3.2.9
# https://github.com/pylint-dev/pylint/tags
ARG KNFSD_PYLINT_VERSION=3.3.8
# https://github.com/semgrep/semgrep/releases
ARG KNFSD_SEMGREP_VERSION=1.134.0
# https://pypi.org/project/shellcheck-py/
ARG KNFSD_SHELLCHECK_PY_VERSION=0.11.0.1
# https://github.com/mvdan/sh/releases
ARG KNFSD_SHFMT_VERSION=3.12.0
# https://github.com/hashicorp/terraform/releases
ARG KNFSD_TERRAFORM_VERSION=1.2.9
# https://github.com/gruntwork-io/terragrunt/releases
ARG KNFSD_TERRAGRUNT_VERSION=0.86.2
# https://github.com/terraform-linters/tflint/releases
ARG KNFSD_TFLINT_VERSION=0.59.1
# https://github.com/aquasecurity/tfsec/releases
ARG KNFSD_TFSEC_VERSION=1.28.14
# https://github.com/aquasecurity/trivy/releases
ARG KNFSD_TRIVY_VERSION=0.65.0

## install golang, delete empty lines and lines containing PATH= in /etc/environment
RUN set -eux \
    && curl -fsSL "https://dl.google.com/go/go${KNFSD_GOLANG_VERSION}.linux-${BUILDARCH}.tar.gz" -o "/tmp/go${KNFSD_GOLANG_VERSION}.linux-${BUILDARCH}.tar.gz" \
    && sudo tar -C /usr/local -xzf "/tmp/go${KNFSD_GOLANG_VERSION}.linux-${BUILDARCH}.tar.gz" \
    && rm "/tmp/go${KNFSD_GOLANG_VERSION}.linux-${BUILDARCH}.tar.gz" \
    && sudo sed -i -e '/^PATH=/d' -e '/^$/d' /etc/environment
ENV PATH="$PATH:/usr/local/go/bin"

## configure GOPROXY=direct for both ${USERNAME} and root
RUN go env -w GOPROXY=direct
RUN sudo go env -w GOPROXY=direct

## configure cache golang dependencies
RUN --mount=type=cache,id=knfsd-go-cache,target=/home/${USERNAME}/.cache/go-build \
    --mount=type=cache,id=knfsd-go-mod-cache,target=/home/${USERNAME}/go/pkg/mod

## install golangci-lint
RUN set -eux \
    && curl -sSfL "https://raw.githubusercontent.com/golangci/golangci-lint/master/install.sh" \
    | sh -s -- -b "$(go env GOPATH)/bin" v${KNFSD_GOLANGCI_LINT_VERSION} \
    && mkdir -p "/home/${USERNAME}/.cache/golangci-lint" \
    && echo "export GOLANGCI_LINT_CACHE=/home/${USERNAME}/.cache/golangci-lint" >> /home/${USERNAME}/.bashrc

## configure golangci-lint cache
RUN --mount=type=cache,id=knfsd-golangci-lint-cache,target=/home/${USERNAME}/.cache/golangci-lint

## install golang tools
RUN go install mvdan.cc/sh/v3/cmd/shfmt@v${KNFSD_SHFMT_VERSION}
RUN go install github.com/editorconfig-checker/editorconfig-checker/v3/cmd/editorconfig-checker@v${KNFSD_EDITORCONFIG_VERSION}
ENV PATH="$PATH:/home/${USERNAME}/go/bin"

## create pre-commit cache directory
RUN mkdir -p "/home/${USERNAME}/.cache/pre-commit"
ENV PRE_COMMIT_HOME="/home/${USERNAME}/.cache/pre-commit"

## change current working directory
WORKDIR /tmp

## install packer
RUN set -eux \
    && curl -fsSL "https://releases.hashicorp.com/packer/${KNFSD_PACKER_VERSION}/packer_${KNFSD_PACKER_VERSION}_linux_${BUILDARCH}.zip" \
    --output packer.zip && sudo unzip -q -o packer.zip -d /usr/local/bin && rm packer.zip
RUN mkdir -p "/home/${USERNAME}/.packer.d/plugins"
ENV PACKER_PLUGIN_PATH="/home/${USERNAME}/.packer.d/plugins"

## install terraform
RUN set -eux \
    && curl -fsSL "https://releases.hashicorp.com/terraform/${KNFSD_TERRAFORM_VERSION}/terraform_${KNFSD_TERRAFORM_VERSION}_linux_${BUILDARCH}.zip" \
    --output terraform.zip && sudo unzip -q -o terraform.zip -d /usr/local/bin && rm terraform.zip
RUN mkdir -p "/home/${USERNAME}/.terraform.d/plugin-cache"
ENV TF_PLUGIN_CACHE_DIR="/home/${USERNAME}/.terraform.d/plugin-cache"

## install tflint
RUN set -eux \
    && curl -fsSL "https://github.com/terraform-linters/tflint/releases/download/v${KNFSD_TFLINT_VERSION}/tflint_linux_${BUILDARCH}.zip" \
    --output tflint.zip && sudo unzip -q -o tflint.zip -d /usr/local/bin && rm tflint.zip

## install tfsec
RUN set -eux \
    && curl -fsSL "https://github.com/aquasecurity/tfsec/releases/download/v${KNFSD_TFSEC_VERSION}/tfsec_${KNFSD_TFSEC_VERSION}_linux_${BUILDARCH}.tar.gz" \
    --output tfsec.tar.gz && tar -xf tfsec.tar.gz tfsec && rm tfsec.tar.gz && sudo install tfsec /usr/local/bin && rm -rf tfsec

## install trivy
RUN set -eux \
    && ARCH=$([ "${BUILDARCH}" = "arm64" ] && echo "ARM64" || echo "64bit") \
    && curl -fsSL "https://github.com/aquasecurity/trivy/releases/download/v${KNFSD_TRIVY_VERSION}/trivy_${KNFSD_TRIVY_VERSION}_Linux-${ARCH}.deb" \
    --output trivy.deb && sudo dpkg -i trivy.deb && rm trivy.deb

## install bats-core
RUN set -eux \
    && curl -fsSL "https://github.com/bats-core/bats-core/archive/refs/tags/v${KNFSD_BATS_CORE_VERSION}.zip" \
    --output bats-core.zip && unzip -q -o bats-core.zip && sudo ./bats-core-${KNFSD_BATS_CORE_VERSION}/install.sh /usr/local \
    && rm -rf bats-core.zip bats-core-${KNFSD_BATS_CORE_VERSION}

## install terragrunt
RUN set -eux \
    && sudo curl -fsSL "https://github.com/gruntwork-io/terragrunt/releases/download/v${KNFSD_TERRAGRUNT_VERSION}/terragrunt_linux_${BUILDARCH}" \
    --output /usr/local/bin/terragrunt && sudo chmod +x /usr/local/bin/terragrunt

## create venv, activate, install/upgrade pip/pipx, ensure path global
RUN set -eux \
    && sudo python3 -m venv /home/${USERNAME}/.venv \
    && sudo /home/${USERNAME}/.venv/bin/pip install -qq --upgrade pip pipx \
    && sudo /home/${USERNAME}/.venv/bin/pipx ensurepath -qq --global

## pipx install system-wide binaries into isolated virt envs
RUN set -eux \
    && sudo /home/${USERNAME}/.venv/bin/pipx install -qq --global \
    "tzupdate" \
    "black==${KNFSD_BLACK_VERSION}" \
    "checkov==${KNFSD_CHECKOV_VERSION}" \
    "codespell==${KNFSD_CODESPELL_VERSION}" \
    "pre-commit==${KNFSD_PRECOMMIT_VERSION}" \
    "shellcheck-py==${KNFSD_SHELLCHECK_PY_VERSION}" \
    "semgrep==${KNFSD_SEMGREP_VERSION}"

## check versions available: $ pip index versions <package-name>
RUN set -eux \
    && sudo /home/${USERNAME}/.venv/bin/pip install -qq --break-system-packages \
    "boto3==${KNFSD_BOTO3_VERSION}" \
    "mypy==${KNFSD_MYPY_VERSION}" \
    "pylint==${KNFSD_PYLINT_VERSION}" \
    "psycopg==${KNFSD_PSYCOPG_VERSION}"

## set timezone/date to local location
RUN sudo tzupdate
