#!/bin/sh

# Utility for running password reset script from outside container

docker exec -e RESET_USERNAME="$1" -e RESET_PASSWORD="$2" $(docker ps | fgrep docker_ibexfarm | awk '{ print $1; }') /bin/bash -c "PERL5LIB=\$IBEXFARM_src_dir/lib perl \$IBEXFARM_src_dir/script/ResetPassword.pl \$RESET_USERNAME \$RESET_PASSWORD"
