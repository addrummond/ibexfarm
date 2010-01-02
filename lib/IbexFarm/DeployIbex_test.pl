use warnings;
use strict;

use IbexFarm::DeployIbex;

deploy(
    name => "Foo",
    hashbang => "/bin/py",
    external_config_url => "http://localhost:3000/config",
    pass_params => 1,
    www_dir => "/tmp/www"
);
