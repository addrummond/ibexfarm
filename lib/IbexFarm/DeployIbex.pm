package IbexFarm::DeployIbex;

use strict;
use warnings;

use base 'Exporter';

use IbexFarm::FNames;
use File::Spec::Functions qw( splitpath splitdir catfile catdir );
use Fcntl qw( :flock );
use Archive::Tar;
use Cwd;
use File::Copy;

# Will only work reliably with ASCII strings.
my $to_py_escaped_string = sub {
    my $s = shift;
    my $r = '"';
    for (my $i = 0; $i < length($s); ++$i) {
        $r .= "\\x" . sprintf("%x", ord(substr($s, $i, 1)));
    }
    $r .= '"';
    return $r;
};

my @WRITABLE;
for my $p (@{IbexFarm->config->{writable}}) {
    push @WRITABLE, catfile(split /\//, $p);
}

# Args: deployment_dir, ibex_archive, ibex_archive_root_dir, name, hashbang, external_config_url, pass_params, www_dir, www_dir_perms.
sub deploy {
    my %args = @_;
    use YAML;

    IbexFarm::FNames::is_ok_fname($args{name}) or die "Bad name!";

    my $dd = catdir($args{deployment_dir}, $args{name});
    if (! -d $dd)
        { mkdir $dd or die "Could not create deployment dir '$dd': $!"; }
    my $oldcwd = getcwd();
    chdir $dd or die "Could not change PWD to deployment dir: $!.";
    my $tar = Archive::Tar->new($args{ibex_archive}) or die "Could not open archive.";
    $tar->extract() || die "Could not extract archive";

    # This file keeps a record of which of the files in the archive are
    # considered suitable for modification by the user. (Since this might
    # change from version to version, we keep a record on disk for each
    # experiment.)
    open my $wable, (">" . catfile($dd, $args{ibex_archive_root_dir}, 'WRITABLE')) or die "Unable to open 'WRITABLE' file: $!";
    for my $wf (@WRITABLE) { print $wable "$wf\n" or die "Unable to write to 'WRITABLE' file: $!"; }
    close $wable or die "Unable to close 'WRITABLE' file: $!";

    # This file keeps a record of files which the user has uploaded.
    # These are considered to be writable by the user.
    open my $upl, (">" . catfile($dd, $args{ibex_archive_root_dir}, 'UPLOADED')) or die "Unable to open 'UPLOADED' file: $!";
    close $upl or die "Unable to close 'UPLOADED' filed: $!";

    # This file just contains the ibex version.
    open my $version, (">" . catfile($dd, $args{ibex_archive_root_dir}, 'VERSION')) or die "Unable to open 'VERSION' file: $!";
    print $version IbexFarm->config->{ibex_version}, "\n";
    close $version or die "Unable to close 'VERSION' file: $!";

    for my $f ($tar->list_files) {
        my ($vol, $dir, $fname) = splitpath($f);
        if ($fname eq "server.py") { # Add config header to server.py.
            open my $sdotpyfh, "+<$f" or die "Unable to open server.py: $!";
            local $/;
            my $contents = <$sdotpyfh> || die "Unable to read contents of server.py: $!";
            flock $sdotpyfh, LOCK_EX or die "Unable to lock server.py: $!";
            truncate $sdotpyfh, 0 or die "Unable to truncate server.py: $!";
            seek $sdotpyfh, 0, 0 or die "Unable to seek server.py: $!"; # Probably redundant.
            if ($args{hashbang}) { print $sdotpyfh "#!$args{hashbang}\n"; }
            if ($args{external_config_url}) {
                print $sdotpyfh "EXTERNAL_CONFIG_URL = ", $to_py_escaped_string->($args{external_config_url}), "\n";
                print $sdotpyfh "EXTERNAL_CONFIG_PASS_PARAMS = " . ($args{pass_params} ? "True" : "False") . "\n";
                print $sdotpyfh "EXTERNAL_CONFIG_METHOD = 'GET'\n\n";
            }
            print $sdotpyfh $contents;
            close $sdotpyfh or die "Unable to close server.py: $!";

            chmod 0755, $f or die "Unable to chmod 0755 server.py: $!";
        }

        if ($args{www_dir}) {
            my @ds = splitdir($dir);
            if ($ds[$#ds-1] eq "www") { # Copy the files in the www dir somewhere else if this was specified.
                my $ddd = catdir($args{www_dir}, $args{name});
                if (! -d $ddd) { mkdir $ddd or die "Unable to create www dir '$ddd': $!"; }
                # Copy the file.
                copy $f, $ddd or die "Unable to copy file in www dir: $!";
                if ($fname eq "server.py") {
                    chmod 0755, catfile($ddd, $fname) or die "Unable to chmod 0755 server.py after copying: $!";
                }
            }
        }
    }

    $tar->clear;

    chdir $oldcwd or die "Could not return to old PWD: $!";
}

our @EXPORT = qw( deploy );

1;
