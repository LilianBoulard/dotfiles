#!/bin/bash
set -euo pipefail

# Install Ansible if not present
if ! command -v ansible-playbook &>/dev/null; then
    sudo apt-get update && sudo apt-get install -y ansible
fi

# Run the playbook
ansible-playbook -i localhost, -c local --ask-become-pass \
    "${CHEZMOI_SOURCE_DIR}/ansible/setup.yml"
