#!/bin/sh

# Utility for running password reset script from outside container

docker exec $(docker ps | fgrep docker_ibexfarm | awk '{ print $1; }') /bin/bash -c "PERL5LIB=\$IBEXFARM_src_dir/lib perl \$IBEXFARM_src_dir/script/ResetPassword.pl $1 $2"
