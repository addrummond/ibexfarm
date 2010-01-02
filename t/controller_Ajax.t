use strict;
use warnings;
use Test::More tests => 3;

BEGIN { use_ok 'Catalyst::Test', 'IbexFarm' }
BEGIN { use_ok 'IbexFarm::Controller::Ajax' }

ok( request('/ajax')->is_success, 'Request should succeed' );


