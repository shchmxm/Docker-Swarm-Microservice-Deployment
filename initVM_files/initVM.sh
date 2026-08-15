#!/usr/bin/env bash

set -xeuo pipefail
SWARM_TOKEN_FILE='/home/vagrant/app_src/initVM_files/token'

# Docker Installation
### Checking if Docker installed
if systemctl is-active --quiet docker; then
	echo 'Docker is already installed and running, installation skipped'
else
	apt-get update
	apt-get install -y ca-certificates curl
	install -m 0755 -d /etc/apt/keyrings
	curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
	chmod a+r /etc/apt/keyrings/docker.asc
	
	tee /etc/apt/sources.list.d/docker.sources <<-EOF
	Types: deb
	URIs: https://download.docker.com/linux/ubuntu
	Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
	Components: stable
	Signed-By: /etc/apt/keyrings/docker.asc
	EOF
	
	apt-get update
	apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
	systemctl start docker
fi

# Docker Swarm Initialization
if [[ -v $SWARM_NODE_TYPE || -z $SWARM_NODE_TYPE ]]; then
	echo 'Variable SWARM_NODE_TYPE should be set at the Vagrantfile' >&2
	exit 1
else
	echo "SWARM_NODE_TYPE set as $SWARM_NODE_TYPE. Configuring..."
fi

### Adding docker group for default user
sudo usermod -aG docker vagrant

### Manager node
if [[ $SWARM_NODE_TYPE == 'manager' ]]; then
	if [[ $(docker info --format '{{.Swarm.LocalNodeState}}') == 'active' ]]; then
		echo "Host $HOSTNAME already in Swarm as manager"
		docker swarm join-token worker -q > $SWARM_TOKEN_FILE
		echo "Token for adding workers: $(cat $SWARM_TOKEN_FILE)"
	else
		echo "Host $HOSTNAME is not in Swarm, initializing..."
		docker swarm init --advertise-addr $SWARM_MANAGER_IP
		docker swarm join-token worker -q > $SWARM_TOKEN_FILE
		echo "Token for adding workers: $(cat $SWARM_TOKEN_FILE)"
	fi

### Worker node
elif [[ $SWARM_NODE_TYPE == 'worker' ]]; then
	if [[ $(docker info --format '{{.Swarm.LocalNodeState}}') == 'active' ]]; then
		echo "Host $HOSTNAME already in Swarm as worker"
	else
		echo "Host $HOSTNAME is not in Swarm, initializing..."

		echo "Waiting for swarm token from manager..."
		while [ ! -f $SWARM_TOKEN_FILE ] || [ ! -s $SWARM_TOKEN_FILE ]; do
		    sleep 5
		    echo "Keep waiting for token..."
		done

		SWARM_TOKEN=$(cat $SWARM_TOKEN_FILE)
		echo "Token received, joining swarm..."
		docker swarm join --token $SWARM_TOKEN $SWARM_MANAGER_IP:2377
	fi
fi

