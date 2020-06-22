#!/bin/bash
sudo curl https://rpm.gremlin.com/gremlin.repo -o /etc/yum.repos.d/gremlin.repo
sudo yum install -y gremlin gremlind
printf "\nidentifier: $1" >> /etc/gremlin/config.yaml
printf "\nteam_id: $GREMLIN_TEAM_ID\n\ntags:\n  service: kafka\n\n" >> /etc/gremlin/config.yaml
if [ -n "$GREMLIN_TEAM_SECRET" ]; then
	printf "team_secret: $GREMLIN_TEAM_SECRET\n" >> /etc/gremlin/config.yaml
else
	printf "team_certificate: file:///gremlin/gremlin.cert\nteam_private_key: file:///gremlin/gremlin.key\n" >> /etc/gremlin/config.yaml
fi

sudo service gremlind restart