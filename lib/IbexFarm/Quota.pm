package IbexFarm::Quota;

use warnings;
use strict;

use parent 'Exporter';

use File::Find;

# Returns bool saying whether or not the quota is met
# and a string describing the violation (if any).
# Options (all required):
#     max_files_in_dir
#     max_file_size
#     max_total_size
sub check_quota {
    my ($opts, @dirs) = @_;

    my $total;
    my %dirs_file_counts;
    eval {
        find(sub {
            return if $File::Find::name eq "." || $File::Find::name eq "..";
            if (-f $File::Find::name) {
#                print STDERR $File::Find::name, "\n";
                if (defined $dirs_file_counts{$File::Find::dir}) {
                    my $n = ++($dirs_file_counts{$File::Find::dir});
                    if ($n > $opts->{max_files_in_dir}) {
                        die [0, "The directory '" . $File::Find::dir . "' contains more than the maximum permitted number of files ($opts->{max_files_in_dir})"];
                    }
                }
                else
                    { $dirs_file_counts{$File::Find::dir} = 1; }

                my $s = -s $File::Find::name;
                if ($s > $opts->{max_file_size}) {
                    die [0, "The file '$_' exceeded the maximum file size of $opts->{max_file_size} bytes."];
                }
                $total += $s;
            }
        }, @dirs);
    };
    if ($@) {
        die "Weird" unless (ref($@) eq "ARRAY");
        return @{$@};
    }

    if ($total > $opts->{max_total_size}) {
        return (0, "The size of the directory " . $File::Find::dir . " ($total bytes) is greater than the maximum permitted ($opts->{max_total_size} bytes).");
    }
    return (1, "");
}

our @EXPORT_OK = qw( check_quota );

1;
