#!/bin/bash
echo ">>> remove old certbot"
yum remove -y certbot
echo ">>> install epel"
sudo yum install -y epel-release
echo ">>> install snapd"
sudo yum install -y snapd

sudo systemctl enable --now snapd.socket
sudo ln -s /var/lib/snapd/snap /snap
echo ">>> install core"
sudo snap install core; sudo snap refresh core
sleep 5
echo ">>> install core again"
sudo snap install core; sudo snap refresh core
echo ">>> install certbot"
sudo snap install --classic certbot
sudo ln -s /snap/bin/certbot /usr/bin/certbot
echo ">>> done!"
