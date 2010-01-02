use strict;
use warnings;
use Test::More tests => 3;

BEGIN { use_ok 'Catalyst::Test', 'IbexFarm' }
BEGIN { use_ok 'IbexFarm::Controller::Experiment' }

ok( request('/experiment')->is_success, 'Request should succeed' );


