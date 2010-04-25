package IbexFarm::Util;

use strict;
use warnings;

use parent 'Exporter';

use JSON::XS;

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

our @EXPORT_OK = qw( update_json_file );
