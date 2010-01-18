package IbexFarm::PasswordProtectExperiment::Apache;

use warnings;
use strict;

use base 'IbexFarm::PasswordProtectExperiment::Factory';

use IbexFarm;
use File::Spec::Functions qw( catdir catfile );

my $getedir = sub {
    my ($username, $expname) = @_;

    if (IbexFarm->config->{deployment_www_dir}) {
        return catdir(IbexFarm->config->{deployment_www_dir},
                      $username, $expname);
    }
    else {
        return catdir(IbexFarm->config->{deployment_dir},
                      $username, $expname,
                      IbexFarm->config->{ibex_archive_root_dir});
    }
};

sub password_protect_experiment {
    my ($self, $username, $expname, $password) = @_;

    my $edir = $getedir->($username, $expname);

    # Note that '/' cannot appear in an experiment or user name, so this
    # username is guaranteed to be unique.
    my $uname = "$username/$expname";

    system(IbexFarm->config->{password_protect_apache}->{htpasswd},
           "-b",
           IbexFarm->config->{password_protect_apache}->{passwd_file},
           $uname,
           $password);
    if ($? != 0) {
        die "Failure ($?) executing " . IbexFarm->config->{password_protect_apache}->{htpasswd} . " for username $uname";
    }

    open my $htaccess, ">" . catfile($edir, '.htaccess') or die "Unable to create .htaccess file (" . catfile($edir, '.htaccess') . "): $!";
    my $ufile = IbexFarm->config->{password_protect_apache}->{passwd_file};
    print $htaccess <<END
AuthType Basic
AuthName "Restricted Files"
AuthBasicProvider file
AuthUserFile $ufile
Require user $uname
END
;
    close $htaccess or die "Unable to close .htaccess file: $!";

    return $uname;
}

sub password_unprotect_experiment {
    my ($self, $username, $expname) = @_;

    my $edir = $getedir->($username, $expname);
    my $uname = "$username/$expname";

    if (-f catfile($edir, '.htaccess')) {
        unlink catfile($edir, '.htaccess') or die "Unable to remove .htaccess file: $!";
    }

    system(IbexFarm->config->{password_protect_apache}->{htpasswd},
           "-D",
           IbexFarm->config->{password_protect_apache}->{passwd_file},
           $uname);
    if ($? != 0) {
        die "Failure ($?) executing " . IbexFarm->config->{password_protect_apache}->{htpasswd};
    }
}

IbexFarm::PasswordProtectExperiment::Factory->add_factory_type(Apache => __PACKAGE__);
