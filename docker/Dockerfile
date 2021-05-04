FROM alpine:3.8

# Install required alpine linux packages.
RUN apk update && \
    apk add \
      git \
      perl \
      perl-dev \
      musl-dev \
      python \
      apache2 \
      gcc \
      make \
      perl-app-cpanminus \
      perl-namespace-autoclean \
      perl-yaml \
      perl-yaml-xs \
      perl-moose \
      perl-time-hires \
      perl-archive-zip \
      perl-params-classify \
      gdbm \
      apache2-dev \
      curl \
      apache2-utils \
      apache2-ssl \
      shadow \
      vim

# Install the remaining required perl modules using cpanm.
# Build Crypt::Rijndael perl module from source
# because we need to apply a patch to rijndael.h.
# Build modperl from source because no stable alpine package available.
RUN cd /tmp && \
    wget https://archive.apache.org/dist/perl/mod_perl-2.0.10.tar.gz && \
    tar -xzf mod_perl-2.0.10.tar.gz && \
    cd mod_perl-2.0.10/ && \
    perl Makefile.PL MP_APXS=/usr/bin/apxs && \
    make && make install && \
    rm -r /tmp/mod_perl-2.0.10* && \
    cd /tmp && \
    wget https://cpan.metacpan.org/authors/id/L/LE/LEONT/Crypt-Rijndael-1.13.tar.gz && \
    cd /tmp && \
    tar -xzf Crypt-Rijndael-1.13.tar.gz && \
    cd Crypt-Rijndael-1.13/ && \
    perl Makefile.PL && \
    sed -i s/__uint8_t/uint8_t/g rijndael.h && \
    sed -i s/__uint32_t/uint32_t/g rijndael.h && \
    make install && \
    cd .. && \
    rm -rf Crypt-Rijndael-1.13/ && \
    cd ~ && \
    cpanm --notest --no-man-pages --no-wget --curl \
        MooseX::Types \
        MooseX::ConfigFromFile \
        MooseX::Getopt \
        MooseX::Role::Parameterized \
        MooseX::SimpleConfig \
        MooseX::StrictConstructor \
        MooseX::Types::DateTime \
        Catalyst::Devel \
        Catalyst::Plugin::RequireSSL \
        Catalyst::Plugin::Session::Store::File \
        JSON \
        JSON::XS \
        Catalyst::View::JSON \
        Template::Plugin::Filter::Minify::CSS \
        Template::Plugin::Filter::Minify::JavaScript \
        Catalyst::Plugin::Cache::FileCache \
        Catalyst::Plugin::UploadProgress \
        HTML::GenerateUtil \
        Class::Factory \
        Digest \
        Data::Validate::URI \
        Log::Handler \
        Crypt::OpenPGP \
        Variable::Magic \
        DateTime \
        Class::ISA \
        Catalyst::Authentication::User::Hash \
        Catalyst::Plugin::Session::State::Cookie \
        Catalyst::View::TT \
        Catalyst::Plugin::ConfigLoader::Environment \
        Devel::OverloadInfo \
        Net::SSLeay \
        Crypt::Argon2 \
        String::Random

RUN mkdir /ibexfarm.git && \
    git clone --depth 1 https://github.com/addrummond/ibexfarm.git /ibexfarm.git && \
    chown -R apache:apache /ibexfarm.git

# Checkout the revision of github.com/addrummond/ibex corresponding to 0.3.9
# and create a tarball.
RUN mkdir /var/ibexfarm && \
    cd /tmp && \
    git clone https://github.com/addrummond/ibex && \
    cd ibex && \
    git checkout 0e4978d73a085fffd4d1ab73098f4f81e3065c3c && \
    rm -rf .git* && \
    rm -rf docs && \
    rm -rf contrib && \
    rm -f LICENSE README example_lighttpd.conf mkdist.sh server_conf.py && \
    cd .. && \
    tar -czf ibex-deploy-original.tar.gz ibex && \
    mv ibex-deploy-original.tar.gz /var/ibexfarm

RUN mkdir -p /run/apache2 && \
    sed -i 's/^Listen[\t ].*/Listen ${IBEXFARM_port}'/ /etc/apache2/httpd.conf && \
    sed -i 's/LoadModule mpm_prefork/#LoadModule mpm_prefork/' /etc/apache2/httpd.conf && \
    sed -i 's/#LoadModule mpm_worker_module/LoadModule mpm_worker_module/' /etc/apache2/httpd.conf && \
    printf "\
LoadModule perl_module /usr/lib/apache2/mod_perl.so\n\
ServerName localhost\n\
\n\
PerlSwitches -I\${IBEXFARM_src_dir}/lib\n\
PerlModule IbexFarm\n\
\n\
<LocationMatch \"^/(?!(?:static/|ibexexps/))\">\n\
    SetHandler modperl\n\
    PerlResponseHandler IbexFarm\n\
</LocationMatch>\n\
\n\
Alias /static/ \${IBEXFARM_src_dir}/root/static/\n\
<Directory \${IBEXFARM_src_dir}/root/static/>\n\
    Options none\n\
    Require all granted\n\
</Directory>\n\
<Location /static>\n\
    SetHandler default-handler\n\
</Location>\n\
\n\
DocumentRoot \"/var/www\"\n\
\n\
AddHandler cgi-script .py\n\
Alias /ibexexps /ibexdata/ibexexps\n\
\n\
<Directory \"/ibexdata/ibexexps\" >\n\
    Options +ExecCGI +FollowSymLinks\n\
    AllowOverride AuthConfig\n\
    DirectoryIndex experiment.html\n\
    AuthUserFile \"/ibexdata/htpasswd\"\n\
    Require all granted\n\
</Directory>\n\
\n\
#\n\
# Relax access to content within /var/www.\n\
#\n\
<Directory \"/var/www\">\n\
    AllowOverride None\n\
    # Allow open access:\n\
    Require all granted\n\
</Directory>\n\
\n\
# Log to stdout/stderr\n\
ErrorLog /dev/stderr\n\
TransferLog /dev/stdout\n\
\n\
LoadModule cgi_module modules/mod_cgi.so\n\
# SetEnv rather than PerlSetEnv for IBEXFARM_config_url because\n\
# it needs to go through to CGI scripts, not modperl code.\n\
SetEnv IBEXFARM_config_url \"\${IBEXFARM_config_url}\"\n\
Include /etc/apache2/perlenv\n" >> /etc/apache2/httpd.conf

# Create wrapper we use to run httpd.
RUN printf "#!bin/sh\n\
echo 'Starting the Ibex Farm...'\n\
cat <<\"END\">\${IBEXFARM_src_dir}/ibexfarm.yaml\n\
---\n\
name: IbexFarm\n\
\n\
url_prefix: '/'\n\
\n\
webmaster_name: 'IBEX_WEBMASTER'\n\
webmaster_email: 'IBEX_WEBMASTER_EMAIL'\n\
\n\
ibex_archive: '/var/ibexfarm/ibex-deploy.tar.gz'\n\
ibex_version: '0.3.9'\n\
deployment_dir: '/ibexdata/deploy'\n\
deployment_www_dir: '/ibexdata/ibexexps'\n\
\n\
max_fname_length: 150\n\
\n\
dirs: [ 'js_includes', 'css_includes', 'data_includes', 'chunk_includes', 'server_state', 'results' ]\n\
sync_dirs: [ 'js_includes', 'css_includes', 'data_includes', 'chunk_includes', 'server_state' ]\n\
dirs_to_types:\n\
  js_includes: 'text/javascript'\n\
  css_includes: 'text/css'\n\
  data_includes: 'text/javascript'\n\
  chunk_includes: 'text/html'\n\
  server_state: 'text/plain'\n\
  results: 'text/plain'\n\
optional_dirs:\n\
  server_state: 1\n\
  results: 1\n\
writable: [ 'data_includes/*', 'results/*', 'server_state/*','chunk_includes/*' ]\n\
\n\
enforce_quotas: 0\n\
quota_max_files_in_dir: 500\n\
quota_max_file_size: 1048576\n\
quota_max_total_size: 1048576\n\
quota_record_dir: '/ibexdata/quota'\n\
\n\
password_protect_apache:\n\
    htpasswd: '/usr/bin/htpasswd'\n\
    passwd_file: '/ibexdata/htpasswd'\n\
\n\
max_upload_size_bytes: 5242880\n\
\n\
experiment_password_protection: Apache\n\
\n\
git_path: '/usr/bin/git'\n\
git_checkout_timeout_seconds: 25\n\
\n\
event_log_file: '/dev/stdout'\n\
\n\
experiment_base_url: '/ibexexps/'\n\
\n\
python_hashbang: '/usr/bin/python'\n\
\n\
config_url: 'http://localhost/ajax/config'\n\
config_permitted_hosts: ['localhost', '::1']\n\
END\n\
\n\
mkdir -p /ibexdata/deploy\n\
mkdir -p /ibexdata/ibexexps\n\
mkdir -p /ibexdata/quota\n\
mkdir -p /ibexdata/tmp\n\
\n\
if [ -z \"\${IBEXFARM_dont_chown_data_volume}\" ]; then\n\
  chown -R apache:apache /ibexdata\n\
fi\n\
\n\
if [ ! -z \"\${IBEXFARM_spellout_legacy_jank}\" ]; then\n\
    mkdir -p /opt/local\n\
    mkdir -p /opt/local/bin\n\
    ln -sf /usr/bin/python /opt/local/bin/python\n\
    mkdir -p /var/l-apps\n\
    mkdir -p /var/l-apps/ibexfarm\n\
    ln -sf /ibexdata/deploy/ /var/l-apps/ibexfarm/deploy\n\
    ln -sf /ibexdata/deploy /var/ibexfarm/deploy\n\
fi\n\
\n\
cd /tmp\n\
tar -xzf /var/ibexfarm/ibex-deploy-original.tar.gz\n\
if [ \"\${IBEXFARM_ibex_archive_root_dir}\" != \"ibex\" ]; then\n\
    mv ibex \${IBEXFARM_ibex_archive_root_dir}\n\
fi\n\
tar -czf ibex-deploy.tar.gz \${IBEXFARM_ibex_archive_root_dir}\n\
mv ibex-deploy.tar.gz /var/ibexfarm/ibex-deploy.tar.gz\n\
rm -rf \${IBEXFARM_ibex_archive_root_dir}\n\
cd ~\n\
\n\
touch /ibexdata/htpasswd\n\
chown apache:apache /ibexdata/htpasswd\n\
\n\
# Work around issue with PerlSetEnv not liking empty second arg\n\
echo "" > /etc/apache2/perlenv\n\
if [ -n \"\$IBEXFARM_host\" ]; then\n\
    echo PerlSetEnv IBEXFARM_host \\\"\\\${IBEXFARM_host}\\\" >> /etc/apache2/perlenv\n\
fi\n\
if [ -n \"\$IBEXFARM_url_prefix\" ]; then\n\
    echo PerlSetEnv IBEXFARM_url_prefix \\\"\\\${IBEXFARM_url_prefix}\\\" >> /etc/apache2/perlenv\n\
fi\n\
if [ -n \"\$IBEXFARM_webmaster_email\" ]; then\n\
    echo PerlSetEnv IBEXFARM_webmaster_email \\\"\\\${IBEXFARM_webmaster_email}\\\" >> /etc/apache2/perlenv\n\
fi\n\
if [ -n \"\$IBEXFARM_webmaster_name\" ]; then\n\
    echo PerlSetEnv IBEXFARM_webmaster_name \\\"\\\${IBEXFARM_webmaster_name}\\\" >> /etc/apache2/perlenv\n\
fi\n\
if [ -n \"\$IBEXFARM_config_secret\" ]; then\n\
    echo PerlSetEnv IBEXFARM_config_secret \\\"\\\${IBEXFARM_config_secret}\\\" >> /etc/apache2/perlenv\n\
fi\n\
if [ -n \"\$IBEXFARM_config_url_envvar\" ]; then\n\
    echo PerlSetEnv IBEXFARM_config_url_envvar \\\"\\\${IBEXFARM_config_url_envvar}\\\" >> /etc/apache2/perlenv\n\
fi\n\
if [ -n \"\$IBEXFARM_rehash_old_passwords\" ]; then\n\
    echo PerlSetEnv IBEXFARM_rehash_old_passwords \\\"\\\${IBEXFARM_rehash_old_passwords}\\\" >> /etc/apache2/perlenv\n\
fi\n\
if [ -n \"\$IBEXFARM_argon2id_t_cost\" ]; then\n\
    echo PerlSetEnv IBEXFARM_argon2id_t_cost \\\"\\\${IBEXFARM_argon2id_t_cost}\\\" >> /etc/apache2/perlenv\n\
fi\n\
if [ -n \"\$IBEXFARM_argon2id_m_factor\" ]; then\n\
    echo PerlSetEnv IBEXFARM_argon2id_m_factor \\\"\\\${IBEXFARM_argon2id_m_factor}\\\" >> /etc/apache2/perlenv\n\
fi\n\
if [ -n \"\$IBEXFARM_argon2id_parallelism\" ]; then\n\
    echo PerlSetEnv IBEXFARM_argon2id_parallelism \\\"\\\${IBEXFARM_argon2id_parallelism}\\\" >> /etc/apache2/perlenv\n\
fi\n\
if [ -n \"\$IBEXFARM_argon2id_tag_size\" ]; then\n\
    echo PerlSetEnv IBEXFARM_argon2id_tag_size \\\"\\\${IBEXFARM_argon2id_tag_size}\\\" >> /etc/apache2/perlenv\n\
fi\n\
if [ -n \"\$IBEXFARM_argon2id_salt_length\" ]; then\n\
    echo PerlSetEnv IBEXFARM_argon2id_salt_length \\\"\\\${IBEXFARM_argon2id_salt_length}\\\" >> /etc/apache2/perlenv\n\
fi\n\
if [ -n \"\$IBEXFARM_ibex_archive_root_dir\" ]; then\n\
    echo PerlSetEnv IBEXFARM_ibex_archive_root_dir \\\"\\\${IBEXFARM_ibex_archive_root_dir}\\\" >> /etc/apache2/perlenv\n\
fi\n\
if [ -n \"\$IBEXFARM_front_page_html_message\" ]; then\n\
    echo PerlSetEnv IBEXFARM_front_page_html_message \\\"\\\${IBEXFARM_front_page_html_message}\\\" >> /etc/apache2/perlenv\n\
fi\n\
if [ -n \"\$IBEXFARM_enforce_quotas\" ]; then\n\
    echo PerlSetEnv IBEXFARM_enforce_quotas \\\"\\\${IBEXFARM_enforce_quotas}\\\" >> /etc/apache2/perlenv\n\
fi\n\
if [ -n \"\$IBEXFARM_quota_max_files_in_dir\" ]; then\n\
    echo PerlSetEnv IBEXFARM_quota_max_files_in_dir \\\"\\\${IBEXFARM_quota_max_files_in_dir}\\\" >> /etc/apache2/perlenv\n\
fi\n\
if [ -n \"\$IBEXFARM_quota_max_file_size\" ]; then\n\
    echo PerlSetEnv IBEXFARM_quota_max_file_size \\\"\\\${IBEXFARM_quota_max_file_size}\\\" >> /etc/apache2/perlenv\n\
fi\n\
if [ -n \"\$IBEXFARM_quota_max_total_size\" ]; then\n\
    echo PerlSetEnv IBEXFARM_quota_max_total_size \\\"\\\${IBEXFARM_quota_max_total_size}\\\" >> /etc/apache2/perlenv\n\
fi\n\
chown apache:apache /etc/apache2/perlenv\n\
\n\
exec /usr/sbin/httpd -D FOREGROUND\n\
" > /var/ibexfarm/start.sh && \
    chmod +x /var/ibexfarm/start.sh

# Fix the id of the apache user and group so we know what they are
# if doing chowns in the host system.
RUN groupmod -g 987654 apache && \
    usermod -u 987654 apache

EXPOSE 80
ENTRYPOINT ["/var/ibexfarm/start.sh"]
