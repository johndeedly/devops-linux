#!/usr/bin/env bash

exec &> >(while IFS=$'\r' read -ra line; do [ ${#line[@]} -eq 0 ] && continue; TS=$(</proc/uptime); echo -e "[${TS% *}] ${line[-1]}" | tee -a /cidata_log > /dev/tty1; done)

if [ -e /bin/apt ]; then
  LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive apt -y update
  LC_ALL=C yes | LC_ALL=C DEBIAN_FRONTEND=noninteractive apt -y install python3-venv
fi

pushd /root
(
  python3 -m venv .venv
  source .venv/bin/activate

  python3 -m pip install ansible

  tee inventory.yml <<EOF
all:
  children:
    local:
      vars:
        setup_facts: "{{ lookup('file','/var/lib/cloud/instance/config/setup.yml') | from_yaml }}"
      hosts:
        localhost:
          ansible_connection: local
          ansible_python_interpreter: /usr/bin/python3
EOF
  export ANSIBLE_VERBOSITY=0
  export ANSIBLE_PIPELINING=True
  export ANSIBLE_PYTHON_INTERPRETER=/usr/bin/python3
  export ANSIBLE_CALLBACKS_ENABLED=profile_tasks,profile_roles
  export ANSIBLE_USE_PERSISTENT_CONNECTIONS=True
  export ANSIBLE_DEPRECATION_WARNINGS=False
  ansible-playbook -i inventory.yml /var/lib/cloud/instance/playbook/stage-1.yml

  deactivate
)
popd

# sync everything to disk
sync

# cleanup
[ -f "${0}" ] && rm -- "${0}"
