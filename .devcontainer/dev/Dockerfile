# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

## docker build --tag knfsd-dev:latest --file .devcontainer/dev/Dockerfile .
## docker run --platform linux/amd64 --rm --name knfsd-dev --hostname knfsd-dev -it -v /var/run/docker.sock:/var/run/docker.sock knfsd-dev

FROM --platform=${BUILDPLATFORM} public.ecr.aws/lts/ubuntu:24.04

ARG VERSION="1.1.0-alpha.24"

LABEL org.opencontainers.image.source="https://github.com/awslabs/knfsd-file-cache"
LABEL org.opencontainers.image.description="knfsd-file-cache development container image"
LABEL org.opencontainers.image.authors="knfsd-file-cache@amazon.com"
LABEL org.opencontainers.image.vendor="Amazon Web Services"
LABEL org.opencontainers.image.licenses="Apache-2.0"
LABEL org.opencontainers.image.version=${VERSION}

HEALTHCHECK NONE

## set default SHELL to bash
SHELL ["/bin/bash", "-eux", "-c"]

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
RUN apt-get -y -q update && apt-get -y -q upgrade \
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
RUN install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc \
    && chmod a+r /etc/apt/keyrings/docker.asc \
    && echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
        $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

## install docker & cleanup apt pkgs
RUN apt-get -y -q update && apt-get -y -q install \
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
RUN echo "deb http://apt.postgresql.org/pub/repos/apt $(. /etc/os-release && echo "$VERSION_CODENAME")-pgdg main" >> /etc/apt/sources.list.d/pgdg.list \
    && curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /etc/apt/trusted.gpg.d/postgresql.gpg \
    && apt-get -y -q update \
    && apt-get -y -q install postgresql-client \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

## non-root user
ARG USERNAME=ubuntu

## silence sudo usage message, grant sudo rights, symlink python3
RUN echo "Defaults !admin_flag" >> /etc/sudoers.d/disable_admin_file \
    && chmod 0440 /etc/sudoers.d/disable_admin_file \
    && echo ${USERNAME} ALL=\(root\) NOPASSWD:ALL >> /etc/sudoers.d/${USERNAME} \
    && echo "Defaults secure_path=\"/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin:/usr/local/go/bin:/home/${USERNAME}/go/bin:/opt/venv/bin\"" >> /etc/sudoers.d/${USERNAME} \
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
RUN ARCH=$([ "${BUILDARCH}" = "arm64" ] && echo "aarch64" || echo "x86_64") \
    && curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${ARCH}.zip" -o /tmp/awscliv2.zip \
    && unzip -q -o /tmp/awscliv2.zip -d /tmp/aws-cli \
    && sudo bash /tmp/aws-cli/aws/install \
    && rm -rf /tmp/awscliv2.zip /tmp/aws-cli \
    && echo 'complete -C "/usr/local/bin/aws_completer" aws' >> /home/${USERNAME}/.bashrc

## build version args
# https://github.com/bats-core/bats-core/releases
ARG KNFSD_BATS_CORE_VERSION=1.13.0
# https://github.com/psf/black/releases
ARG KNFSD_BLACK_VERSION=26.3.1
# https://github.com/boto/boto3/tags
ARG KNFSD_BOTO3_VERSION=1.42.94
# https://hub.docker.com/r/bridgecrew/checkov/tags
ARG KNFSD_CHECKOV_VERSION=3.2.524
# https://github.com/codespell-project/codespell/releases
ARG KNFSD_CODESPELL_VERSION=2.4.2
# https://github.com/go-delve/delve/tags
ARG KNFSD_DLV_VERSION=1.26.2
# https://github.com/editorconfig-checker/editorconfig-checker/releases
ARG KNFSD_EDITORCONFIG_VERSION=3.6.1
# https://github.com/golangci/golangci-lint/releases
ARG KNFSD_GOLANGCI_LINT_VERSION=2.11.4
# https://go.dev/dl/
ARG KNFSD_GOLANG_VERSION=1.26.2
# https://pkg.go.dev/golang.org/x/tools/gopls
ARG KNFSD_GOPLS_VERSION=0.21.1
# https://github.com/securego/gosec/releases
ARG KNFSD_GOSEC_VERSION=2.25.0
# https://github.com/python/mypy/tags
ARG KNFSD_MYPY_VERSION=1.20.2
# https://github.com/hashicorp/packer/releases
ARG KNFSD_PACKER_VERSION=1.15.1
# https://github.com/pre-commit/pre-commit/releases
ARG KNFSD_PRECOMMIT_VERSION=4.6.0
# https://pypi.org/project/psycopg/
ARG KNFSD_PSYCOPG_VERSION=3.3.3
# https://github.com/pylint-dev/pylint/tags
ARG KNFSD_PYLINT_VERSION=4.0.5
# https://github.com/semgrep/semgrep/releases
ARG KNFSD_SEMGREP_VERSION=1.161.0
# https://pypi.org/project/shellcheck-py/
ARG KNFSD_SHELLCHECK_PY_VERSION=0.11.0.1
# https://github.com/mvdan/sh/releases
ARG KNFSD_SHFMT_VERSION=3.13.1
# https://github.com/hashicorp/terraform/releases
ARG KNFSD_TERRAFORM_VERSION=1.2.9
# https://github.com/gruntwork-io/terragrunt/releases
ARG KNFSD_TERRAGRUNT_VERSION=1.0.2
# https://github.com/terraform-linters/tflint/releases
ARG KNFSD_TFLINT_VERSION=0.62.0
# https://github.com/aquasecurity/trivy/releases
ARG KNFSD_TRIVY_VERSION=0.70.0
# https://pypi.org/project/tzupdate/
ARG KNFSD_TZUPDATE_VERSION=2.1.0
# https://github.com/astral-sh/uv/releases
ARG KNFSD_UV_VERSION=0.11.7

## install golang, delete empty lines and lines containing PATH= in /etc/environment
RUN curl -fsSL "https://dl.google.com/go/go${KNFSD_GOLANG_VERSION}.linux-${BUILDARCH}.tar.gz" -o "/tmp/go${KNFSD_GOLANG_VERSION}.linux-${BUILDARCH}.tar.gz" \
    && sudo tar -C /usr/local -xzf "/tmp/go${KNFSD_GOLANG_VERSION}.linux-${BUILDARCH}.tar.gz" \
    && rm "/tmp/go${KNFSD_GOLANG_VERSION}.linux-${BUILDARCH}.tar.gz" \
    && sudo sed -i -e '/^PATH=/d' -e '/^$/d' /etc/environment
ENV PATH="$PATH:/usr/local/go/bin"

## configure runtime GOPROXY=direct for both ${USERNAME} and root
RUN go env -w GOPROXY=direct
RUN sudo go env -w GOPROXY=direct
ENV GOPATH="/home/${USERNAME}/.cache/go"
ENV GOMODCACHE="/home/${USERNAME}/.cache/go/pkg/mod"

## create go cache/module directories used by mounted volumes at runtime
RUN mkdir -p "/home/${USERNAME}/.cache/go-build" \
    "/home/${USERNAME}/.cache/go/pkg" \
    "/home/${USERNAME}/.cache/golangci-lint"

## install golangci-lint
RUN curl -sSfL "https://raw.githubusercontent.com/golangci/golangci-lint/master/install.sh" \
    | sudo sh -s -- -b /usr/local/bin "v${KNFSD_GOLANGCI_LINT_VERSION}" \
    && mkdir -p "/home/${USERNAME}/.cache/golangci-lint" \
    && echo "export GOLANGCI_LINT_CACHE=/home/${USERNAME}/.cache/golangci-lint" >> /home/${USERNAME}/.bashrc

## install golang tools with caches
RUN --mount=type=cache,target=/home/${USERNAME}/.cache/go-build,uid=1000,gid=1000 \
    --mount=type=cache,target=/home/${USERNAME}/.cache/go/pkg,uid=1000,gid=1000 \
    export GOBIN=/tmp/go-bin \
    && mkdir -p "${GOBIN}" \
    && go install golang.org/x/tools/gopls@v${KNFSD_GOPLS_VERSION} \
    && go install github.com/go-delve/delve/cmd/dlv@v${KNFSD_DLV_VERSION} \
    && go install mvdan.cc/sh/v3/cmd/shfmt@v${KNFSD_SHFMT_VERSION} \
    && go install github.com/securego/gosec/v2/cmd/gosec@v${KNFSD_GOSEC_VERSION} \
    && go install github.com/editorconfig-checker/editorconfig-checker/v3/cmd/editorconfig-checker@v${KNFSD_EDITORCONFIG_VERSION} \
    && sudo install -m 0755 "${GOBIN}/gopls" /usr/local/bin/gopls \
    && sudo install -m 0755 "${GOBIN}/dlv" /usr/local/bin/dlv \
    && sudo install -m 0755 "${GOBIN}/shfmt" /usr/local/bin/shfmt \
    && sudo install -m 0755 "${GOBIN}/gosec" /usr/local/bin/gosec \
    && sudo install -m 0755 "${GOBIN}/editorconfig-checker" /usr/local/bin/editorconfig-checker \
    && rm -rf "${GOBIN}"
ENV PATH="$PATH:/home/${USERNAME}/go/bin"

## create pre-commit cache directory
RUN mkdir -p "/home/${USERNAME}/.cache/pre-commit"
ENV PRE_COMMIT_HOME="/home/${USERNAME}/.cache/pre-commit"

## change current working directory
WORKDIR /tmp

## install packer
RUN curl -fsSL "https://releases.hashicorp.com/packer/${KNFSD_PACKER_VERSION}/packer_${KNFSD_PACKER_VERSION}_linux_${BUILDARCH}.zip" \
    --output packer.zip && sudo unzip -q -o packer.zip -d /usr/local/bin && rm packer.zip
RUN mkdir -p "/home/${USERNAME}/.packer.d/plugins"
ENV PACKER_PLUGIN_PATH="/home/${USERNAME}/.packer.d/plugins"

## install terraform
RUN curl -fsSL "https://releases.hashicorp.com/terraform/${KNFSD_TERRAFORM_VERSION}/terraform_${KNFSD_TERRAFORM_VERSION}_linux_${BUILDARCH}.zip" \
    --output terraform.zip && sudo unzip -q -o terraform.zip -d /usr/local/bin && rm terraform.zip
RUN mkdir -p "/home/${USERNAME}/.terraform.d/plugin-cache"
ENV TF_PLUGIN_CACHE_DIR="/home/${USERNAME}/.terraform.d/plugin-cache"

## install tflint
RUN curl -fsSL "https://github.com/terraform-linters/tflint/releases/download/v${KNFSD_TFLINT_VERSION}/tflint_linux_${BUILDARCH}.zip" \
    --output tflint.zip && sudo unzip -q -o tflint.zip -d /usr/local/bin && rm tflint.zip

## install trivy
RUN ARCH=$([ "${BUILDARCH}" = "arm64" ] && echo "ARM64" || echo "64bit") \
    && curl -fsSL "https://github.com/aquasecurity/trivy/releases/download/v${KNFSD_TRIVY_VERSION}/trivy_${KNFSD_TRIVY_VERSION}_Linux-${ARCH}.deb" \
    --output trivy.deb && sudo dpkg -i trivy.deb && rm trivy.deb

## install bats-core
RUN curl -fsSL "https://github.com/bats-core/bats-core/archive/refs/tags/v${KNFSD_BATS_CORE_VERSION}.zip" \
    --output bats-core.zip && unzip -q -o bats-core.zip && sudo ./bats-core-${KNFSD_BATS_CORE_VERSION}/install.sh /usr/local \
    && rm -rf bats-core.zip bats-core-${KNFSD_BATS_CORE_VERSION}

## install terragrunt
RUN sudo curl -fsSL "https://github.com/gruntwork-io/terragrunt/releases/download/v${KNFSD_TERRAGRUNT_VERSION}/terragrunt_linux_${BUILDARCH}" \
    --output /usr/local/bin/terragrunt && sudo chmod +x /usr/local/bin/terragrunt

## install uv
RUN curl -fsSL "https://astral.sh/uv/${KNFSD_UV_VERSION}/install.sh" | sudo env UV_UNMANAGED_INSTALL="/usr/local/bin" sh

## uv env vars
ENV UV_LINK_MODE=copy
ENV UV_TOOL_BIN_DIR="/opt/venv/bin"
ENV UV_CACHE_DIR="/home/${USERNAME}/.cache/uv"

## create venv directory permissions for non-root user
RUN sudo mkdir -p "/opt/venv" && sudo chown -R "${USERNAME}:${USERNAME}" "/opt/venv"

## create venv with uv, set env vars
RUN uv venv /opt/venv
ENV VIRTUAL_ENV="/opt/venv"
ENV PATH="/opt/venv/bin:${PATH}"

## uv tool install binaries into isolated virt envs
RUN --mount=type=cache,target=/home/${USERNAME}/.cache/uv,uid=1000,gid=1000 \
    uv tool install -q "tzupdate==${KNFSD_TZUPDATE_VERSION}" \
    && uv tool install -q "black==${KNFSD_BLACK_VERSION}" \
    && uv tool install -q "checkov==${KNFSD_CHECKOV_VERSION}" \
    && uv tool install -q "codespell==${KNFSD_CODESPELL_VERSION}" \
    && uv tool install -q "pre-commit==${KNFSD_PRECOMMIT_VERSION}" \
    && uv tool install -q "shellcheck-py==${KNFSD_SHELLCHECK_PY_VERSION}" \
    && uv tool install -q "semgrep==${KNFSD_SEMGREP_VERSION}"

## check versions available: $ uv pip index versions <package-name>
RUN --mount=type=cache,target=/home/${USERNAME}/.cache/uv,uid=1000,gid=1000 \
    uv pip install -q \
    "boto3==${KNFSD_BOTO3_VERSION}" \
    "mypy==${KNFSD_MYPY_VERSION}" \
    "pylint==${KNFSD_PYLINT_VERSION}" \
    "psycopg==${KNFSD_PSYCOPG_VERSION}"

## set timezone/date to local location
RUN sudo tzupdate 2> /dev/null
