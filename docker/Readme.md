These instructions guide you through setting up an Ibex Farm instance on a
Linode running CentOS 8. Unlike the earlier version of these instructions at
https://adrummond.net/posts/ibexfarmdocker, these instructions assume that you
have a domain and want to use Caddy's automatic SSL cert management via
[Letsencrypt](https://letsencrypt.org/).

For simplicity, these instructions assume that you will be logging in using a
username and password. It is advisible to disable the option to log in via a
username and password over ssh (and use keys instead).

## Creating a linode

[Linode](https://linode.com) is one of many cloud hosting providers. It's cheap
and easy to use compared to more sophisticated options like
[AWS](https://aws.amazon.com).

If you anticipate hosting large number of experiments (more than a few hundred),
then check out the ‘Storage Space’ section below.

After creating a linode account, create a linode running CoreOS Container Linux.
Note that the Apache and Docker configuration is quite tricky, so don't expect
these exact instructions to work on other distros without significant
modification.

If the IP address of your linode is e.g. `192.192.192.192`, you can ssh in as
follows:

```sh
ssh root@192.192.192.192
```

## Setting up the linode

Ssh in as root (as in the example above). Execute the following commands:

```sh
adduser ibex
passwd ibex
usermod -aG wheel ibex
dnf update -y
dnf install -y firewalld git wget	
systemctl enable firewalld
rm -f /etc/firewalld/zones/public.xml
firewall-cmd --complete-reload
firewall-cmd --zone=public --add-service=http --permanent
firewall-cmd --zone=public --add-service=https --permanent
firewall-cmd --zone=public --add-service=ssh --permanent # may show 'already enabled' warning
firewall-cmd --zone=public --add-port=443/tcp --permanent
firewall-cmd --zone=public --add-port=80/tcp --permanent
firewall-cmd --zone=public --add-masquerade --permanent
firewall-cmd --reload
ulimit -n 8192 # for caddy
shutdown -r now
```

The linode will now reboot, terminating your ssh session. In a couple of
minutes, ssh in again as user `ibex` (e.g. `ssh ibex@192.192.192.192`). Install
docker and docker-compose:

```sh
sudo dnf config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo
sudo dnf install -y --nobest docker-ce
sudo curl -L "https://github.com/docker/compose/releases/download/1.25.4/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
sudo usermod -aG docker ibex
```

We can now start the docker daemon:

```sh
sudo systemctl enable docker
sudo systemctl start docker
```

Allow the `ibex` user to do Docker stuff by adding it to the `docker` group:

```sh
sudo usermod -aG docker ibex
logout # you have to log out and log in again for the new group perms to take effect
```

Ssh in again as `ibex`. Create directory called `ibexdata` to hold the Ibex Farm data:

```sh
mkdir ~/ibexdata
```

Build the Ibex Farm Docker container:

```sh
cd ~
git clone https://github.com/addrummond/ibexfarm
cd ibexfarm/docker
docker build .
```

Configure the webmaster email address and webmaster name for this instance,
together with some other configuration options:

```sh
sudo touch /etc/ibexenv.sh
sudo chown ibex:ibex /etc/ibexenv.sh
echo 'IBEXFARM_webmaster_email="example@example.com"' >> /etc/ibexenv.sh
echo 'IBEXFARM_webmaster_name="Some person"' >> /etc/ibexenv.sh
echo 'IBEXFARM_url_prefix="/"' >> /etc/ibexenv.sh
echo 'IBEXFARM_experiment_base_url="/ibexexps"' >> /etc/ibexenv.sh
```

If you chose to build from source, you may want to add the following definition
to ibexenv.sh to make the Ibex Farm use the Perl code in `~/ibexfarm/docker`
rather than the code inside the Docker container:

```sh
sudo echo 'IBEXFARM_src_dir=/code' >> /etc/ibexenv.sh
```

Source the preceding definitions and add them to the system profile:

```sh
set -o allexport ; source /etc/ibexenv.sh ; set +o allexport
sudo bash -c 'echo "set -o allexport ; source /etc/ibexenv.sh ; set +o allexport" > /etc/profile.d/ibex.sh'
```

Allow systemd to manage Docker containers:

```sh
sudo setsebool -P container_manage_cgroup on
```

Create a systemd service called `ibexfarm-server` to run the docker container:

```sh
printf "[Unit]\nDescription=Ibex Farm server\nWants=docker.service\nAfter=docker.service\n[Service]\nLimitNOFILE=8192\nEnvironmentFile=/etc/ibexenv.sh\nUser=ibex\nRestart=always\nRestartSec=10\nExecStartPre=/usr/bin/bash -c 'cat /etc/ibexenv.sh | xargs -n 1 echo > /tmp/ibexenv_docker'\nExecStart=/usr/local/bin/docker-compose -f /home/ibex/ibexfarm/docker/docker-compose.yml up\nExecStop=/usr/local/bin/docker-compose -f /home/ibex/ibexfarm/docker/docker-compose.yml down\n[Install]\nWantedBy=multi-user.target\n" | sudo bash -c 'tee > /etc/systemd/system/ibexfarm-server.service'
sudo systemctl daemon-reload
```

Finally, start Ibex Farm using the following commands:

```sh
sudo systemctl start ibexfarm-server.service
sudo systemctl enable ibexfarm-server.service
```

At this point, if the server is up and running, you should be able to retrieve
`index.html` by running `wget http://localhost:8888`.

## Storage space

If you anticipate hosting lots of experiments on your Ibex Farm instance, you
should store the `ibexdata` volume on a linode volume rather than on the root
filesystem of the linode. Whereas there's no straightforward way to enlarge a
linode's root filesystem, it's easy to enlarge a linode volume. See the [docker
documentation](https://docs.docker.com/engine/reference/commandline/volume_create/)
(and in particular the `--opt device` option to `docker volume create`) for more
info.

## Setting up Caddy with https

**You'll need to get a domain name pointing to the IP of your linode before
following these instructions.**

**Remember that DNS propagation can take a while, so wait for a few hours after
you've associated your domain name with your linode's IP address.**

This section steps through the process of setting up https using a free
[letsencrypt](https://letsencrypt.org/) certificate.

First, define your hostname:

```sh
echo 'IBEXFARM_host="my.domain.name"' >> /etc/ibexenv.sh
set -o allexport ; source /etc/ibexenv.sh ; set +o allexport
```

Install Caddy:

```sh
cd ~
curl -o caddy.tar.gz https://caddyserver.com/download/linux/amd64?license=personal&telemetry=off
sudo mkdir /caddy
sudo useradd -r -d /caddy -M -s /sbin/nologin caddy
sudo chown caddy:caddy /caddy
sudo tar -xzf caddy.tar.gz -C /caddy
sudo chown -R caddy:caddy /caddy
rm ~/caddy.tar.gz
sudo -u caddy mkdir /caddy/ssl
sudo setcap CAP_NET_BIND_SERVICE=+eip /caddy/caddy
```

Create a systemd service for Caddy:

```sh
printf "[Unit]\nDescription=Caddy HTTP/2 web server\nDocumentation=https://caddyserver.com/docs\nAfter=network-online.target\nWants=network-online.target systemd-networkd-wait-online.service\n[Service]\nRestart=on-abnormal\nUser=caddy\nGroup=caddy\nEnvironment=CADDYPATH=/caddy/ssl\nEnvironmentFile=/etc/ibexenv.sh\nExecStartPre=/bin/bash -c 'env > /caddy/env_on_startup'\nExecStart=/caddy/caddy -log stdout -agree=true -conf=/caddy/caddy.conf\nExecReload=/bin/kill -USR1 \$MAINPID\nKillMode=mixed\nKillSignal=SIGQUIT\nTimeoutStopSec=5s\nLimitNOFILE=1048576\nLimitNPROC=512\nPrivateTmp=true\nPrivateDevices=true\nReadWriteDirectories=/caddy/ssl\nCapabilityBoundingSet=CAP_NET_BIND_SERVICE\nAmbientCapabilities=CAP_NET_BIND_SERVICE\nNoNewPrivileges=true\n[Install]\nWantedBy=multi-user.target\n" | sudo bash -c 'tee > /etc/systemd/system/caddy.service'
sudo systemctl daemon-reload
```

Set up Caddy with automatic SSL cert management:

```sh
sudo -u caddy bash -c 'printf "{\$IBEXFARM_host} {\n  log syslog\n  proxy {\$IBEXFARM_url_prefix} http://127.0.0.1:8888 { without {\$IBEXFARM_url_prefix} }\n  proxy {\$IBEXFARM_experiment_base_url} http://127.0.0.1:8888\n  tls {\$IBEXFARM_webmaster_email}\n}\n" > /caddy/caddy.conf'
```

Make sure that you've set `IBEXFARM_webmaster_email` to a real
email address in `/etc/ibexenv.sh`. This email address will be associated
with your SSL cert.

### Start Caddy

Finally, start and enable the Caddy systemd service:

```sh
sudo setenforce 0
sudo systemctl start caddy.service
sudo systemctl enable caddy.service
```

Unfortunately, it appears to be necessary to disable SELinux for Caddy to start.
I haven't been able to find a resolution for this issue.

You should now have access to your Ibex Farm instance over https. Caddy has been
configured to redirect any http requests to https.

You may wish to create an `example` user with an `example` experiment, so that
the link on the homepage isn't broken.

## The docker apache user

It can be useful to create a `dapache` user and group with the ids of the
`apache` user and group inside the Docker container:

```sh
sudo groupadd dapache -g 987654
sudo useradd -g dapache -u 987654 -s /sbin/nologin dapache
```

You can then e.g. `chown` a file to `dapache:dapache` to have it owned by the
Docker `apache` user.

## Long startup times

If you have a large set of existing experiments, you may find that the
`ibexfarm-server` process takes a long time to start up. (It takes about 10
minutes on `spellout.net`.) This is due to a recursive `chown` executed in the
entrypoint. After the server has been started for the first time, it is no
longer necessary to run this command. You can set
`IBEXFARM_dont_chown_data_volume=1` to prevent the `chown` from executing and
reduce startup times. 