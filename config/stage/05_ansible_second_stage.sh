#!/usr/bin/env bash

exec &> >(while IFS=$'\r' read -ra line; do [ ${#line[@]} -eq 0 ] && continue; TS=$(</proc/uptime); echo -e "[${TS% *}] ${line[-1]}" | tee -a /cidata_log > /dev/tty1; done)

pushd /root
(
  source .venv/bin/activate

  export ANSIBLE_VERBOSITY=0
  export ANSIBLE_PIPELINING=True
  export ANSIBLE_PYTHON_INTERPRETER=/usr/bin/python3
  export ANSIBLE_CALLBACKS_ENABLED=profile_tasks,profile_roles
  export ANSIBLE_USE_PERSISTENT_CONNECTIONS=True
  export ANSIBLE_DEPRECATION_WARNINGS=False
  ansible-playbook -i inventory.yml /var/lib/cloud/instance/playbook/stage-2.yml

  deactivate
)
popd

# sync everything to disk
sync

# cleanup
[ -d /root/.venv ] && rm -r /root/.venv
[ -f "${0}" ] && rm -- "${0}"
