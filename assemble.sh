#!/usr/bin/env bash

BUILD=(
    archlinux
    debian-13
    ubuntu-24
)
SESSION=devops-linux-$(LC_ALL=C tr -dc A-Za-z0-9 </dev/urandom | head -c 8)
echo "tmux session: $SESSION"

first=1
for task in "${BUILD[@]}"; do
    cp config/setup.yml "config/$task.yml"
    yq -i -y \
      --arg newoutput "output/$task" \
      --arg newiso "$task-x86_64-cidata.iso" \
      --arg newdistro "$task" \
      '.packer.output_path = $newoutput | .packer.iso_path = $newiso | .setup.distro = $newdistro' "config/$task.yml"
    if (( first )); then
        tmux new-session -d -s "$SESSION" './pipeline.sh -c "config/'"$task"'.yml"'
        first=0
    else
        tmux split-window -h -t "$SESSION":1 './pipeline.sh -c "config/'"$task"'.yml"'
    fi
    echo "wait 10s after $task..."
    sleep 10
done

tmux select-layout -t "$SESSION":1 even-horizontal
tmux attach -t "$SESSION"
