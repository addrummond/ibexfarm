#!/bin/bash

#
# This script either automates or fails to automate the deployment of Ibex Farm
# on a Linode server running CentOS 7.
#
# It should be run as follows:
#
#    sudo SERVER_HOST=foo.bar.com IBEX_VERSION=0.3.6 bash linodedeploy.sh
#
# If you don't have a domain set up, you can just pass the IP address of your
# EC2 instance as the value for SERVER_HOST. If you want to use a custom ibex
# tarball, you can set IBEX_URL. Otherwise, the script will automatically
# download the tarball for the given ibex version (if it exists).
#
# The script starts the httpd server automatically. You can manage it using the
# commands:
#
#    sudo service httpd (re)start/stop
#
# Experiments go in /var/www/ibexexps and /var/ibexfarm/deploy.
#
# You may want to edit webmaster_name and webmaster_email in the
# write_ibex_config() function below.
#

if [ -z "$SERVER_HOST" ]; then
    echo "You must define the SERVER_HOST environment variable."
    echo "Script will now exit (without doing anything)"
    exit 1
fi

ibex_version_error() {
    echo "You must define the IBEX_VERSION environment variable."
    echo "This error may also be produced if IBEX_VERSION does not consist"
    echo "solely of letters, digits and '.', '-' or '_' characters."
    echo "Script will now exit (without doing anything)"
    exit 1
}
if [ -z "$IBEX_VERSION" ]; then
    ibex_version_error
fi
if ! [[ "$IBEX_VERSION" =~ ^[0-9A-Za-z_.-]+$ ]]; then
    ibex_version_error
fi

write_ibex_config() {
    cat <<EOFEOF > /var/ibexfarm/ibexfarm/ibexfarm.yaml
---
name: IbexFarm

webmaster_name: "Alex"
webmaster_email: "a.d.drummond@gmail.com"

ibex_archive: "/var/ibexfarm/ibex-deploy.tar.gz"
ibex_archive_root_dir: "ibex-deploy"
ibex_version: "${IBEX_VERSION}"
deployment_dir: "/var/ibexfarm/deploy"
deployment_www_dir: "/var/www/ibexexps"

max_fname_length: 150

dirs: [ "js_includes", "css_includes", "data_includes", "chunk_includes", "server_state", "results" ]
sync_dirs: [ "js_includes", "css_includes", "data_includes", "chunk_includes", "server_state" ]
dirs_to_types:
  js_includes: 'text/javascript'
  css_includes: 'text/css'
  data_includes: 'text/javascript'
  chunk_includes: 'text/html'
  server_state: 'text/plain'
  results: 'text/plain'
optional_dirs:
  server_state: 1
  results: 1
writable: [ "data_includes/*", "results/*", "server_state/*", "chunk_includes/*" ]

enforce_quotas: 0
quota_max_files_in_dir: 500
quota_max_file_size: 1048576
quota_max_total_size: 1048576
quota_record_dir: "/tmp/quota"

password_protect_apache:
    htpasswd: "/usr/bin/htpasswd"
    passwd_file: "/etc/httpd/conf/httpdpasswd"

max_upload_size_bytes: 1048576

experiment_password_protection: Apache

git_path: "/usr/bin/git"
git_checkout_timeout_seconds: 25

event_log_file: "/tmp/event_log"

experiment_base_url: "http://${SERVER_HOST}/ibexexps/"

python_hashbang: "/opt/local/bin/python"

config_url: "http://${SERVER_HOST}/ibexfarm/ajax/config"
config_permitted_hosts: ["localhost", "${SERVER_HOST}", "spellout.user.openhosting.com", "spellout.net"]

EOFEOF
}

append_to_apache_config() {
    cat <<EOFEOF >>/etc/httpd/conf/httpd.conf

ServerName localhost

PerlSwitches -I/var/ibexfarm/ibexfarm/lib
PerlModule IbexFarm
    <Location /ibexfarm>
        SetHandler modperl
        PerlResponseHandler IbexFarm
    </Location>

    Alias /ibexfarm/static/ /var/ibexfarm/ibexfarm/root/static/
    <Directory /var/ibexfarm/ibexfarm/root/static/>
        Options none
        Require all granted
    </Directory>
    <Location /ibexfarm/static>
        SetHandler default-handler
    </Location>

DocumentRoot "/var/www"

AddHandler cgi-script .py

<Directory "/var/www/ibexexps" >
    Options +ExecCGI +FollowSymLinks
    AllowOverride AuthConfig
    DirectoryIndex experiment.html
</Directory>
EOFEOF
}

append_to_etc_hosts() {
    # URLs containing spellout.user.openhosting.com and spellout.net are
    # scattered through all of the server.py scripts, so it's best just to
    # redirect these to localhost. (Nice design idea there, me.)

    cat <<EOFEOF >>/etc/hosts

127.0.0.1   spellout.user.openhosting.com
127.0.0.1   spellout.net
EOFEOF
}

write_domain_home() {
    cat <<EOFEOF >/var/www/index.html
<html>
<body>
You are probably looking for the <a href="/ibexfarm">Ibex Farm</a>.
</body>
</html>
EOFEOF
    if [ $? -ne 0 ]; then
        exit $?
    fi
    chown apache:apache /var/www/index.html
}

# Install any available updates.
yes | yum update &&

# Install basic utilities.
yum install -y git &&

# Install apache.
yum install -y httpd &&

# Often useful for various things (e.g. gdcp).
yum install -y python-pip &&

#
# BEGINNING OF HIDEOUS PERL INSTALLATION.
#
yum install -y gcc &&
yum install -y perl-App-cpanminus.noarch &&
yum install -y perl-namespace-autoclean &&
yum install -y epel-release &&
yum install -y mod_perl &&
cpanm --notest Moose &&
cpanm --notest MooseX::Types &&
cpanm --notest MooseX::ConfigFromFile MooseX::Getopt MooseX::Role::Parameterized MooseX::SimpleConfig MooseX::StrictConstructor MooseX::Types::DateTime &&
cpanm --notest Namespace::Autoclean &&
cpanm --notest Time::HiRes &&
cpanm --notest Time::Piece &&
cpanm --notest Catalyst::Devel &&
cpanm --notest Catalyst::Plugin::RequireSSL &&
cpanm --notest Catalyst::Plugin::Session::Store::FastMmap &&
cpanm --notest JSON &&
cpanm --notest Catalyst::View::JSON &&
cpanm --notest Template::Plugin::Filter::Minify::CSS &&
cpanm --notest Template::Plugin::Filter::Minify::JavaScript &&
cpanm --notest Catalyst::Plugin::Cache::FastMmap &&
cpanm --notest Catalyst::Plugin::UploadProgress &&
cpanm --notest HTML::GenerateUtil &&
cpanm --notest Class::Factory &&
cpanm --notest JSON::XS &&
cpanm --notest Digest &&
cpanm --notest Archive::Zip &&
cpanm --notest Data::Validate::URI &&
cpanm --notest Log::Handler &&
cpanm --notest Crypt::OpenPGP &&
cpanm --notest Params::Classify &&
cpanm --notest Variable::Magic &&
cpanm --notest DateTime &&
cpanm --notest Class::ISA &&
cpanm --notest Catalyst::Authentication::User::Hash &&
cpanm --notest Catalyst::Plugin::Session::State::Cookie &&
cpanm --notest Catalyst::View::TT &&
cpanm --notest Archive::Tar &&
#
# END OF HIDEOUS PERL INSTALLATION.
#

# Set up deployment dir etc.
mkdir /var/ibexfarm &&
git clone https://github.com/addrummond/ibexfarm.git /var/ibexfarm/ibexfarm &&
chown -R apache:apache /var/ibexfarm/ &&
mkdir /var/ibexfarm/deploy &&
chown apache:apache /var/ibexfarm/deploy/ &&
mkdir /var/www/ibexexps &&
chown apache:apache /var/www/ibexexps &&

# Set up ibex tarball.
if [ -n "$IBEX_URL" ]; then
    IBEX_TARBALL_URL="$IBEX_URL"
else
    IBEX_TARBALL_URL="https://webspr.googlecode.com/files/ibex-${IBEX_VERSION}.tar.gz"
fi
wget "$IBEX_TARBALL_URL" -O /tmp/ibextarball.tar.gz &&
tar -C /tmp -xzf /tmp/ibextarball.tar.gz &&
cd /tmp/ibex-${IBEX_VERSION} &&
# The cp utility on Amazon linux only supports -x, not -X (!)
sed -e 's/-X/-x/g' mkdist.sh > mkdist2.sh &&
sh mkdist2.sh deploy &&
cp dist/ibex-deploy.tar.gz /var/ibexfarm &&
chown apache:apache /var/ibexfarm/ibex-deploy.tar.gz &&
rm /tmp/ibextarball.tar.gz &&
rm -r "/tmp/ibex-${IBEX_VERSION}" &&
cd ~ &&

# Set up http password protection config.
touch /etc/httpd/conf/httpdpasswd &&
chown apache:apache /etc/httpd/conf/httpdpasswd &&

# Python, on the original Ibex Farm VPS, was installed in /opt/local, so we
# add a symlink to make the transition easier. (Old experiments assume this
# path in the hashbangs of their server.py files.)
mkdir /opt/local &&
mkdir /opt/local/bin &&
ln -s /usr/bin/python /opt/local/bin/python &&

# These paths are hardcoded in various old experiments, so we need to create
# symlinks.
mkdir /var/l-apps &&
mkdir /var/l-apps/ibexfarm &&
ln -s /var/ibexfarm/deploy/ /var/l-apps/ibexfarm/deploy &&
chown -R apache:apache /var/l-apps/ &&

# Write/modify various config files and index.html for http://spellout.net
write_ibex_config &&
append_to_apache_config &&
append_to_etc_hosts &&
write_domain_home &&

service httpd start &&

echo &&
echo &&
echo &&
echo "*********************************************************************" &&
echo "* Everything appears to have been set up successfully.              *" &&
echo "*                                                                   *" &&
echo "* Run:                                                              *" &&
echo "*                                                                   *" &&
echo "*     sudo service httpd (re)start/stop                             *" &&
echo "*                                                                   *" &&
echo "* to manage the web server, which should already have started       *" &&
echo "*                                                                   *" &&
echo "*********************************************************************" &&
echo "** Make sure that you have set up the linode to allow              **" &&
echo "**            outside connections on port 80.                      **" &&
echo "*********************************************************************" &&
echo
