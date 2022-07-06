#!/bin/bash

## Ensure $HOME exists when starting
if [ ! -d "${HOME}" ]; then
  mkdir -p "${HOME}"
fi

## Add current (arbitrary) user to /etc/passwd and /etc/group
#if ! whoami &>/dev/null; then
#  if [ -w /etc/passwd ]; then
#    echo "${USER_NAME:-user}:x:$(id -u):0:${USER_NAME:-user} user:${HOME}:/bin/bash" >>/etc/passwd
#    echo "${USER_NAME:-user}:x:$(id -u):" >>/etc/group
#  fi
#fi
export USER_ID=$(id -u)
export GROUP_ID=$(id -g)
USER=${USER_NAME:-default}
if [ "$USER_ID" != "0" ] && [ "$USER_ID" != "1001" ]; then
  if [ -w /etc/passwd ]; then
    grep -v "^${USER}:" /etc/passwd >/tmp/passwd
    echo "${USER}:x:$(id -u):0:${USER} user:${HOME}:/bin/bash" >>/tmp/passwd
    cat /tmp/passwd >/etc/passwd
    rm /tmp/passwd
  fi
fi

## Grant access to projects volume in case of non root user with sudo rights
if [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
  sudo chown "$(id -u):$(id -g)" /projects
fi

#if [ -f "${HOME}"/.venv/bin/activate ]; then
#  source "${HOME}"/.venv/bin/activate
#fi

## Setup $PS1 for a consistent and reasonable prompt
if [ -w "${HOME}" ] && [ ! -f "${HOME}"/.bashrc ]; then
  echo "PS1='[\u@\h \W]\$ '" >"${HOME}"/.bashrc
fi

exec "$@"
