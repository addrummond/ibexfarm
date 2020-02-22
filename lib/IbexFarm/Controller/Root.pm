package IbexFarm::Controller::Root;

use strict;
use warnings;
use parent 'Catalyst::Controller';
use File::Spec::Functions qw( catdir catfile );
use Archive::Zip;
use IbexFarm::AjaxHeaders qw( ajax_headers );
use IbexFarm::Util;

#
# Sets the actions in this controller to be registered with no prefix
# so they function identically to actions created in MyApp.pm
#
__PACKAGE__->config->{namespace} = '';

# Used for detecting IE (so that we don't send special IE CSS if it's not required).
sub begin :Private {
    my ($self, $c) = @_;
    if ($c->req->headers->{'user-agent'} =~ /MSIE/) { 
        $c->stash->{IS_IE} = 1;
    }
}

my $experiment_count_cache = 0;
my $experiment_count_cache_last_update = 0;
my $get_experiment_count = sub {
    if ($experiment_count_cache && time - $experiment_count_cache_last_update < 120) {
        return $experiment_count_cache;
    }
    else {
        my $count = 0;
        my $DIR;
        opendir $DIR, catdir(IbexFarm->config->{deployment_dir}) or return $experiment_count_cache;
        while (defined (my $e = readdir($DIR))) {
            next if IbexFarm::Util::is_special_file($e);
            if (-d catdir(IbexFarm->config->{deployment_dir}, $e)) {
                my $DIR2;
                unless (opendir $DIR2, catdir(IbexFarm->config->{deployment_dir}, $e)) {
                    close $DIR;
                    return $experiment_count_cache;
                }
                while (defined (my $d = readdir($DIR2))) { ++$count if ($d !~ /^\./ && $d ne IbexFarm->config->{USER_FILE_NAME}); }
                closedir $DIR2;
            }
        }
        closedir $DIR;
        $experiment_count_cache = $count;
        $experiment_count_cache_last_update = time;
        return $count;
    }
};

sub index :Path :Args(0) {
    my ( $self, $c ) = @_;

    $c->stash->{experiment_base_url} = IbexFarm->config->{experiment_base_url};
    $c->stash->{experiment_count} = $get_experiment_count->();
    $c->stash->{example_experiment_user} = IbexFarm->config->{example_experiment_user} || "example";
    $c->stash->{example_experiment_name} = IbexFarm->config->{example_experiment_name} || "example";
    $c->stash->{webmaster_email} = IbexFarm->config->{webmaster_email};
    $c->stash->{template} = "frontpage.tt";
}

sub githelp :Path("githelp") :Args(0) {
    my ($self, $c) = @_;

    $c->stash->{timeout} = IbexFarm->config->{git_checkout_timeout_seconds};
    $c->stash->{back_uri} = $c->flash->{back_uri};
    $c->stash->{experiment_name} = $c->flash->{experiment_name};
    $c->stash->{template} = "githelp.tt";
}

sub zip_archive :Path("zip_archive") {
    my ($self, $c) = (shift, shift);
    my $experiment_name = shift or $c->detach('default');
    $experiment_name =~ /^([^.]+)\.zip$/;
    ($experiment_name = $1) or $c->detach('default');
    $c->detach('unauthorized') unless ($c->user_exists);

    my $edir = catdir(IbexFarm->config->{deployment_dir}, $c->user->username, $experiment_name, IbexFarm->config->{ibex_archive_root_dir});
    my $zip = Archive::Zip->new();
    for my $dir (@{IbexFarm->config->{dirs}}) {
        if (-d (my $dd = catdir($edir, $dir))) {
            my $zdir = $zip->addDirectory($dir);
            opendir my $DIR, $dd or die "Unable to open dir: $!";
            while (defined (my $entry = readdir($DIR))) {
                next if IbexFarm::Util::is_special_file($entry);
                $zip->addFile(catfile($dd, $entry), "$dir/$entry"); # Archive::Zip always uses '/'.
            }
        }
    }

    # Neat Perl trick: you can apparently open a reference to a string to get a file handle.
    my $sbuf = "";
    open my $sbuffh, "+<", \$sbuf;
    $zip->writeToFileHandle($sbuffh) == Archive::Zip::AZ_OK or die "Error compressing zip file: $!";

    ajax_headers($c, 'application/zip', '', 200);
    $c->res->body($sbuf);
    return 0;
}

sub bad_request :Path {
    my ($self, $c) = @_;
    $c->response->body('Bad request');
    $c->response->status(404);
}

sub unauthorized :Path {
    my ($self, $c) = @_;
    $c->response->body('You do not have permission to access this page.');
    $c->response->status(401);
}

sub default :Path {
    my ($self, $c) = @_;
    $c->response->body('Page not found');
    $c->response->status(404);
}

sub end : ActionClass('RenderView') {}

sub auto : Private {
    my ($self, $c) = @_;
    $c->req->base(URI->new(IbexFarm->config->{url_prefix}));
}

1;
