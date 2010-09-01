package IbexFarm::Controller::Experiment;

use strict;
use warnings;
use parent 'Catalyst::Controller';
use File::Spec::Functions qw( catfile catdir );

sub manage :Absolute {
    my ($self, $c, $experiment) = (shift, shift, shift);
    return $c->res->redirect($c->uri_for('/login')) unless $c->user_exists;
    return $c->res->redirect($c->uri_for('/myaccount')) unless $experiment;
    $c->detach('Root', 'default') if scalar(@_);

    # Open USER file to get saved values for git repo/branch.
    open my $uf, catfile(IbexFarm->config->{deployment_dir}, $c->user->username, IbexFarm->config->{USER_FILE_NAME}) or
        die "Unable to open '", IbexFarm->config->{USER_FILE_NAME}, "' file for reading: $!";
    local $/;
    my $contents = <$uf>;
    defined $contents or die "Error reading '", IbexFarm->config->{USER_FILE_NAME}, "' file: $!";
    close $uf or die "Error closing '", IbexFarm->config->{USER_FILE_NAME}, "' file: $!";
    my $json = JSON::XS::decode_json($contents) or die "Error decoding JSON";

    # So that other pages can point back to this one.
    $c->flash->{back_uri} = $c->uri_for('/manage/' . $experiment);
    $c->flash->{experiment_name} = $experiment;

    $c->stash->{experiment_base_url} = IbexFarm->config->{experiment_base_url};
    $c->stash->{experiment} = $experiment;
    $c->stash->{ibex_version} =
        IbexFarm::Util::get_experiment_version(catdir(IbexFarm->config->{deployment_dir}, $c->user->username, $experiment));

    # In the old (dumb) days we stored the git URL per user rather than per user per experiment.
    # So that we don't have to update old USER files, we still honor the old way. Note that
    # since the code for handling the new way comes after this code, the new way will override
    # the old way. (I.e. once a user has a default git URL for all his experiments, the old
    # 'git_repo_url' and 'git_branch_url' options will be ignored.)
    # However, if the user creates a new experiment, we don't want an old default git URL
    # specified by 'git_repo_url' to become the default for that experiment (it should start
    # with no default). Therefore, for any experiment created after the date that this
    # modification was made to the code, we ignore 'git_repo_url' entirely.
    # We use ctime (which though not strictly creation time, is close enough). Not sure
    # how this will behave on non-UNIX platforms which (a) cause Perl to report a ctime
    # but (b) may (?) have a significantly different semantics for it.
    my $expdir = catdir(IbexFarm->config->{deployment_dir}, $c->user->username, $experiment);
    # Was getting weird errors using File::Stat, for some reason. Should sort these out at some
    # point so that this isn't required.
    my @stats = stat($expdir) or die "Unable to stat experiment directory '$expdir'";
    my $ctime = $stats[10];
    if ($json->{git_repo_url} && ((! $ctime) || $ctime < 1280000116)) { # 1280000116 = 07/24/2010 3:35pm EST
	$json->{git_repo_branch} or die "git_repo_url but no git_repo_branch";
	$c->stash->{git_repo_url} = $json->{git_repo_url};
	$c->stash->{git_repo_branch} = $json->{git_repo_branch};
    }
    # The new way.
    if ($json->{git_repos} && $json->{git_repos}{$experiment}) {
	($json->{git_repos}{$experiment}{url} && $json->{git_repos}{$experiment}{branch}) or
            die "'url' and 'branch' keys should both be present";
	$c->stash->{git_repo_url} = $json->{git_repos}{$experiment}{url};
	$c->stash->{git_repo_branch} = $json->{git_repos}{$experiment}{branch};
    }

    $c->stash->{template} = "manage.tt";
}

1;
