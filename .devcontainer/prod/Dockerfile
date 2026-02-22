# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

## docker build --tag knfsd-prod:latest --file .devcontainer/prod/Dockerfile .
## docker run --platform linux/amd64 --rm --name knfsd-prod --hostname knfsd-prod -it -v /var/run/docker.sock:/var/run/docker.sock knfsd-prod

FROM --platform=${BUILDPLATFORM} public.ecr.aws/lts/ubuntu:24.04

ARG VERSION="1.1.0-alpha.21"

LABEL org.opencontainers.image.source="https://github.com/awslabs/knfsd-file-cache"
LABEL org.opencontainers.image.description="knfsd-file-cache production container image"
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
RUN set -eux \
    && apt-get -y -q update && apt-get -y -q upgrade \
    && apt-get -y -q install -o=Dpkg::Use-Pty=0 \
    apt-utils \
    bash-completion \
    curl \
    git \
    jq \
    locales \
    openssh-client \
    python3-pip \
    python3-venv \
    sudo \
    tzdata \
    unzip \
    vim \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

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

## non-root user
ARG USERNAME=ubuntu

## silence sudo usage message, grant sudo rights
RUN set -eux \
    && echo "Defaults !admin_flag" >> /etc/sudoers.d/disable_admin_file \
    && chmod 0440 /etc/sudoers.d/disable_admin_file \
    && echo ${USERNAME} ALL=\(root\) NOPASSWD:ALL >> /etc/sudoers.d/${USERNAME} \
    && echo 'Defaults secure_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin"' >> /etc/sudoers.d/${USERNAME} \
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
# https://github.com/hashicorp/packer/releases
ARG KNFSD_PACKER_VERSION=1.15.0
# https://github.com/hashicorp/terraform/releases
ARG KNFSD_TERRAFORM_VERSION=1.2.9

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

## create venv, activate, install/upgrade pip/pipx, ensure path global
RUN set -eux \
    && sudo python3 -m venv /home/${USERNAME}/.venv \
    && sudo /home/${USERNAME}/.venv/bin/pip install -qq --upgrade pip pipx \
    && sudo /home/${USERNAME}/.venv/bin/pipx ensurepath -qq --global

## install tzupdate
## pipx install system-wide binaries into isolated virt envs
RUN set -eux \
    && sudo /home/${USERNAME}/.venv/bin/pipx install -qq --global \
    "tzupdate"

## set timezone/date to local location
RUN sudo tzupdate
