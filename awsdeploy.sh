#!/bin/bash

#
# This script either automates or fails to automate the deployment of Ibex Farm
# on an Amazon AWS instance running the Amazon Linux distro.
#
# It should be run as follows on a fresh instance:
#
#    sudo bash awsdeploy.sh
#

write_ibex_config() {
    cat <<EOFEOF > /home/ibex/ibexfarm/ibexfarm.yaml
---
name: IbexFarm

webmaster_name: "Alex"
webmaster_email: "a.d.drummond@gmail.com"

ibex_archive: "/var/ibexfarm/ibex-deploy.tar.gz"
ibex_archive_root_dir: "ibex-deploy"
ibex_version: "0.3.6"
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

max_upload_size_bytes: 1048576

experiment_password_protection: Apache

git_path: "/usr/bin/git"
git_checkout_timeout_seconds: 25

event_log_file: "/tmp/event_log"

experiment_base_url: "http://spellout.net/ibexexps/"

python_hashbang: "/opt/local/bin/python"

config_url: "http://spellout.user.openhosting.com/ibexfarm/ajax/config"
config_permitted_hosts: ["localhost", "spellout.user.openhosting.com", "spellout.net"]

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
        Order allow,deny
        Allow from all
    </Directory>
    <Location /ibexfarm/static>
        SetHandler default-handler
    </Location>

DocumentRoot "/var/www"

AddHandler cgi-script .py

<Directory />
Options +ExecCGI
</Directory>
EOFEOF
}

append_to_etc_hosts() {
    cat <<EOFEOF >>/etc/hosts

127.0.0.1   spellout.user.openhosting.com
127.0.0.1   spellout.net
EOFEOF
}

yum update &&

# Stop pointless services running.
service sendmail stop &&

# Instal basic utilities.
yes | yum install git &&

#
# BEGINNING OF HIDEOUS PERL INSTALLATION.
#
yes | yum install mod_perl mod_perl-devel &&
yes | yum install perl-App-cpanminus.noarch &&
yes | yum install perl-Moose &&
yes | yum install perl-MooseX-Types &&
yes | yum install perl-namespace-autoclean &&
yes | yum install perl-MooseX-Types perl-MooseX-ConfigFromFile perl-MooseX-Getopt perl-MooseX-Role-Parameterized perl-MooseX-SimpleConfig perl-MooseX-StrictConstructorperl-MooseX-Types-DateTime &&
yes | yum install perl-Time-HiRes &&
yes | yum install perl-Time-Piece &&
yes | yum install gcc &&
cpanm Catalyst::Devel &&
cpanm Catalyst::Plugin::RequireSSL &&
cpanm Catalyst::Plugin::Session::Store::FastMmap &&
cpanm JSON &&
cpanm Catalyst::View::JSON &&
cpanm Template::Plugin::Filter::Minify::CSS &&
cpanm Template::Plugin::Filter::Minify::JavaScript &&
cpanm Catalyst::Plugin::Cache::FastMmap &&
cpanm Catalyst::Plugin::UploadProgress &&
cpanm HTML::GenerateUtil &&
cpanm Class::Factory &&
cpanm JSON::XS &&
cpanm Digest &&
cpanm Archive::Zip &&
cpanm Data::Validate::URI &&
cpanm Log::Handler &&
cpanm Crypt::OpenPGP &&
cpanm Params::Classify &&
cpanm Variable::Magic &&
cpanm DateTime &&
cpanm Class::ISA &&
cpanm Catalyst::Authentication::User::Hash &&
cpanm Catalyst/Plugin/Session/State/Cookie.pm &&
cpanm Catalyst::View::TT &&
cpanm Archive::Tar &&
#
# END OF HIDEOUS PERL INSTALLATION.
#

# Set up deployment dir etc.
mkdir /var/ibexfarm &&
git clone https://github.com/addrummond/ibexfarm.git /var/ibexfarm/ibexfarm &&
chown -R apache:apache /home/ibex/ibexfarm &&
mkdir /var/ibexfarm/deploy &&
chown apache:apache /var/ibexfarm/deploy/ &&
wget http://gdurl.com/V--j -O /var/ibexfarm/ibex-deploy.tar.gz &&
chown apache:apache /var/ibexfarm/ibex-deploy.tar.gz &&
mkdir /var/www/ibexfarm &&
mkdir /var/www/ibexexps &&
chown apache:apache /var/www/ibexfarm &&
chown apache:apache /var/www/ibexexps &&
mkdir /opt/local &&
mkdir /opt/local/bin &&
ln -s /usr/bin/python /opt/local/bin/python &&

# ...

write_ibex_config &&
append_to_apache_config &&
append_to_etc_hosts
