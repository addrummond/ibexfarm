use warnings;
use strict;

# Gross!

use File::Find;

my @confs;
find(sub {
        if (-f $_ && $_ !~ /~$/ && $_ ne 'findconfigvars.pl') {
            open(my $f, $_);
            for my $l (<$f>) {
                if ($l =~ /IbexFarm->config->{([^}]+)}/) { push @confs, "$1"; }
            }
        }
     }, './');

@confs = sort @confs;
my $prev = '';
@confs = grep { $_ ne $prev && (($prev) = $_) } @confs;
for (@confs) { print "$_\n"; }
