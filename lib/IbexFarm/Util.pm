package IbexFarm::Util;

use strict;
use warnings;

use parent 'Exporter';

use JSON::XS;
use File::Spec::Functions qw( catfile );

sub update_json_file {
    my ($filename, $updatef) = @_;

    open my $f, $filename or die "Unable to open '$filename' for reading: $!";
    local $/;
    my $contents = <$f>;
    close $f or die "Unable to close '$filename' after reading: $!";
    my $json = JSON::XS::decode_json($contents);
    die "Bad JSON in '$filename' file" unless (ref($json) eq "HASH");

    # Note: in principle, we could read version 1 of the file, then
    # someone else could write version 2, and we'd end up writing
    # version 1.1 instead of version 2.1. Not worth guarding against
    # this since if multiple updates are occuring at the same time,
    # unexpected results are going to occur whatever order we process
    # the updates.

    my $newjson = $updatef->($json);
    open my $of, ">>$filename", or die "Unable to open '$filename': $!";
    flock $of, 2 or die "Unable to lock '$filename': $!";
    truncate $of, 0 or die "Unable to truncate '$filename': $!";
    seek $of, 0, 0 or die "Really?: $!";
    print $of JSON::XS::encode_json($newjson);
    flock $of, 8; # Unlock;
    close $of or die "Unable to close '$filename' after writing: :$!";

    return $newjson;
}

# Files to skip when going through the contents of a directory.
sub is_special_file {
    return shift =~ /^[:.]/;
}

sub get_experiment_version {
    my $edir = shift;
    open my $vf, catfile($edir, IbexFarm->config->{ibex_archive_root_dir}, 'VERSION') or die "Unable to open VERSION file";
    my $version = <$vf>;
    close $vf or die "Unable to close 'VERSION' file: $!";
    die "Unable to read from 'VERSION' file: $!" unless (defined $version);
    $version =~ s/\s*$//;
    return $version;
}

our @EXPORT_OK = qw( update_json_file is_special_file );
