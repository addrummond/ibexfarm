FROM alpine:3.8

# Install required alpine linux packages.
RUN apk update
RUN apk add \
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
    gdbm \
    apache2-dev \
    curl \
    apache2-utils
RUN cd /tmp && \
    wget http://apache.org/dist/perl/mod_perl-2.0.10.tar.gz && \
    tar -xzf mod_perl-2.0.10.tar.gz && \
    cd mod_perl-2.0.10/ && \
    perl Makefile.PL MP_APXS=/usr/bin/apxs && \
    make && make install

# Load modperl in httpd conf
RUN echo >> /etc/apache2/httpd.conf && \
    echo "LoadModule perl_module /usr/lib/apache2/mod_perl.so" >> /etc/apache2/httpd.conf

# Build Crypt::Rijndael perl module manually because we need to apply a patch
# to rijndael.h.
RUN cd /tmp && \
    wget https://cpan.metacpan.org/authors/id/L/LE/LEONT/Crypt-Rijndael-1.13.tar.gz && \
    tar -xzf Crypt-Rijndael-1.13.tar.gz && \
    cd Crypt-Rijndael-1.13/ && \
    perl Makefile.PL && \
    sed -i s/__uint8_t/uint8_t/g rijndael.h && \
    sed -i s/__uint32_t/uint32_t/g rijndael.h && make install

# Install the remaining required perl modules using cpanm.
RUN cpanm --notest --no-man-pages --no-wget --curl \
    Moose \
    MooseX::Types \
    MooseX::ConfigFromFile \
    MooseX::Getopt \
    MooseX::Role::Parameterized \
    MooseX::SimpleConfig \
    MooseX::StrictConstructor \
    MooseX::Types::DateTime \
    Time::HiRes \
    Time::Piece \
    Catalyst::Devel \
    Catalyst::Plugin::RequireSSL \
    Catalyst::Plugin::Session::Store::FastMmap \
    JSON Catalyst::View::JSON \
    Template::Plugin::Filter::Minify::CSS \
    Template::Plugin::Filter::Minify::JavaScript \
    Catalyst::Plugin::Cache::FastMmap \
    Catalyst::Plugin::UploadProgress \
    HTML::GenerateUtil \
    Class::Factory JSON::XS \
    Digest Archive::Zip \
    Data::Validate::URI \
    Log::Handler \
    Crypt::OpenPGP \
    Params::Classify \
    Variable::Magic \
    DateTime \
    Class::ISA \
    Catalyst::Authentication::User::Hash \
    Catalyst::Plugin::Session::State::Cookie \
    Catalyst::View::TT \
    Archive::Tar \
    Catalyst::Plugin::ConfigLoader::Environment

# Set up deployment dirs.
RUN mkdir /var/ibexfarm && \
    git clone https://github.com/addrummond/ibexfarm.git /var/ibexfarm/ibexfarm && \
    chown -R apache:apache /var/ibexfarm/

# Checkout the revision of github.com/addrummond/ibex corresponding to 0.3.9
# and create a tarball.
RUN cd /tmp && \
    git clone https://github.com/addrummond/ibex && \
    cd ibex && \
    git checkout 9e903f9 && \
    rm -rf .git && \
    cd .. && \
    tar -czf ibex-deploy.tar.gz ibex && \
    mv ibex-deploy.tar.gz /var/ibexfarm

RUN touch /etc/apache2/conf.d/httpdpasswd && \
    chown apache:apache /etc/apache2/conf.d/httpdpasswd

# This is the dir apache2 wants to put its PID file in.
RUN mkdir /run/apache2

# Add domain home
RUN printf "<!DOCTYPE html><html>\n\
<body>\n\
You are probably looking for the <a href="/ibexfarm">Ibex Farm</a>.\n\
</body>\n\
</html>\n" > /var/www/index.html

# Main ibex farm config.
RUN printf "---\n\
name: IbexFarm\n\
\n\
webmaster_name: 'IBEX_WEBMASTER'\n\
webmaster_email: 'IBEX_WEBMASTER_EMAIL'\n\
\n\
ibex_archive: '/var/ibexfarm/ibex-deploy.tar.gz'\n\
ibex_archive_root_dir: 'ibex'\n\
ibex_version: '0.3.9'\n\
deployment_dir: '/var/ibexfarm/deploy'\n\
deployment_www_dir: '/var/www/ibexexps'\n\
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
quota_record_dir: '/tmp/quota'\n\
\n\
password_protect_apache:\n\
    htpasswd: '/usr/bin/htpasswd'\n\
    passwd_file: '/etc/apache2/conf.d/httpdpasswd'\n\
\n\
max_upload_size_bytes: 1048576\n\
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
config_url: 'http://localhost/ibexfarm/ajax/config'\n\
config_permitted_hosts: ['localhost', '::1']\n" > /var/ibexfarm/ibexfarm/ibexfarm.yaml

## Append to Apache config
RUN printf "ServerName localhost\n\
\n\
PerlSwitches -I/var/ibexfarm/ibexfarm/lib\n\
PerlModule IbexFarm\n\
    <Location /ibexfarm>\n\
        SetHandler modperl\n\
        PerlResponseHandler IbexFarm\n\
    </Location>\n\
\n\
    Alias /ibexfarm/static/ /var/ibexfarm/ibexfarm/root/static/\n\
    <Directory /var/ibexfarm/ibexfarm/root/static/>\n\
        Options none\n\
        Require all granted\n\
    </Directory>\n\
    <Location /ibexfarm/static>\n\
        SetHandler default-handler\n\
    </Location>\n\
\n\
DocumentRoot \"/var/www\"\n\
\n\
AddHandler cgi-script .py\n\
Alias "/ibexexps" "/ibexexps"\n\
\n\
<Directory \"/ibexexps\" >\n\
    Options +ExecCGI +FollowSymLinks\n\
    AllowOverride AuthConfig\n\
    DirectoryIndex experiment.html\n\
    Require all granted\n\
</Directory>\n\
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
PerlSetEnv IBEXFARM_webmaster_email \${IBEXFARM_webmaster_email}\n\
PerlSetEnv IBEXFARM_webmaster_name \${IBEXFARM_webmaster_name}\n" >> /etc/apache2/httpd.conf

# Fix handling of base URL in Catalyst
RUN echo 'sub auto : Private { my ($self, $c) = @_; $c->req->base(URI->new("/ibexfarm/")); }; 1' >> /var/ibexfarm/ibexfarm/lib/IbexFarm/Controller/Root.pm

EXPOSE 80
ENTRYPOINT ["/usr/sbin/httpd", "-D", "FOREGROUND"]
