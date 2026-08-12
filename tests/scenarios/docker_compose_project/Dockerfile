FROM docker:25.0.5-dind-alpine3.19

RUN apk upgrade --no-cache \
    && apk add --no-cache \
      bash \
      dcron \
      logrotate \
      openssh-server \
      python3 \
      sudo \
      util-linux \
    && ssh-keygen -A \
    && adduser -D -s /bin/bash ansibletest \
    && echo 'ansibletest:scenario-unused-password' | chpasswd \
    && echo 'ansibletest ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/90-ansibletest \
    && chmod 0440 /etc/sudoers.d/90-ansibletest

EXPOSE 22
