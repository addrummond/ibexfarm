package IbexFarm::CheckEmail;
use warnings;
use strict;

# There are of course existing modules for doing this; I just want to make
# sure that we're using exactly the same regexp on the client and server side
# (and in the DB; as it turns out I haven't bothered doing client-side
# JS validation).

use parent 'Exporter';

sub is_ok_email {
    return shift =~ /^[a-z0-9!#$%&'*+\/=?^_`{|}~-]+(?:\.[a-z0-9!#$%&'*+\/=?^_`{|}~-]+)*@(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+(?:[A-Z]{2}|com|org|net|gov|mil|biz|info|mobi|name|aero|jobs|museum)\b$/;
}

our @EXPORT = qw( is_ok_email );
