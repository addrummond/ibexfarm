use warnings;
use strict;

# Gross!

use File::Find;

my @confs;
find(sub {
        if (-f $_ && $_ !~ /~$/ && $_ ne 'findconfigvars.pl') {
            open(my $f, $_);
	    my $line = 1;
            for my $l (<$f>) {
                if ($l =~ /IbexFarm->config->{([^}]+)}/) { push @confs, { varname => "$1", filename => $File::Find::name, line => $line } ; }
		++$line;
            }
        }
     }, './');

@confs = sort { $a->{varname} cmp $b->{varname} } @confs;
my $prev = { varname => '' };
@confs = grep { $_->{varname} ne $prev->{varname} && (($prev) = $_) } @confs;
for (@confs) { print $_->{varname}, " in ", $_->{filename}, ":", $_->{line}, "\n"; }
