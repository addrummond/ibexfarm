package IbexFarm::FNames;
use warnings;
use strict;

use IbexFarm;

use parent 'Exporter';

sub is_ok_fname {
    my $fname = shift;
    return 0 if length($fname) > IbexFarm->config->{max_fname_length};
    return $fname =~ /^[A-Za-z0-9_-][A-Za-z0-9_.-]*$/;
}

use constant OK_CHARS_DESCRIPTION => "letters, numbers, '.', '-' and '_'";

our @EXPORT = qw( is_ok_fname OK_CHARS_DESCRIPTION );
