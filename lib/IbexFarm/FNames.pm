package IbexFarm::FNames;
use warnings;
use strict;

use parent 'Exporter';

sub is_ok_fname {
    my $fname = shift;
    return $fname =~ /^[A-Za-z0-9_.-]*$/; # Keep in sync with mkdb.sql.
}

use constant OK_CHARS_DESCRIPTION => "letters, numbers, '.', '-' and '_'";

our @EXPORT = qw( is_ok_fname OK_CHARS_DESCRIPTION );
