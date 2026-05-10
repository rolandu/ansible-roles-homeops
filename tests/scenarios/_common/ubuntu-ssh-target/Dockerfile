# Keep this on Ubuntu 22.04 for now. The controller-side Ansible package used
# by this repo can fail against Ubuntu 24.04's Python 3.12 with missing
# ansible.module_utils.six imports.
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      openssh-server \
      openssh-client \
      python3 \
      sudo \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /run/sshd \
    && useradd --create-home --shell /bin/bash ansibletest

EXPOSE 22

CMD ["/usr/sbin/sshd", "-D", "-e"]
