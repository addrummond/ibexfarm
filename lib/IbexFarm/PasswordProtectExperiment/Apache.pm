package IbexFarm::PasswordProtectExperiment::Apache;

use warning;
use strict;

use base 'Exporter';

use IbexFarm;

sub password_protect_experiment {
    my ($username, $expname, $password) = @_;

    my $edir;
    if (IbexFarm->config->{deployment_www_dir}) {
        $edir = catdir(IbexFarm->config->{deployment_www_dir}, $username, $expname);
    }
    else {
        $edir = catdir(IbexFarm->config->{deployment_dir},
                       $username, $expname,
                       IbexFarm->config->{ibex_archive_root_dir});
    }

    # Note that '/' cannot appear in an experiment or user name, so this
    # username is guaranteed to be unique.
    my $uname = $username/$expname;

    system(IbexFarm->config->{password_protect_apache}->{htpasswd},
           "-b",
           IbexFarm->config->{password_protect_apache}->{passwd_file},
           $username,
           $password);
    if ($? != 0) {
        die "Failure executing " . IbexFarm->config->{password_protect_apache}->{htpasswd};
    }

    open my $htaccess, catfile($edir, '.htaccess') or die "Unable to create .htaccess file: $!";
    my $ufile = IbexFarm->config->{password_protect_apache}->{passwd_file};
    print $htacces <<END
AuthType Basic
AuthName "Restricted Files"
AuthBasicProvider file
AuthUserFile $ufile
Require user $uname
    END
    close $htaccess or die "Unable to close .htaccess file: $!";

    return $uname;
}

our @EXPORT_OK = ( password_protect_experiment );
