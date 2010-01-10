package IbexFarm::Controller::Root;

use strict;
use warnings;
use parent 'Catalyst::Controller';
use File::Spec::Functions qw( catdir );

#
# Sets the actions in this controller to be registered with no prefix
# so they function identically to actions created in MyApp.pm
#
__PACKAGE__->config->{namespace} = '';

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
            if (-d catdir(IbexFarm->config->{deployment_dir}, $e)) {
                my $DIR2;
                unless (opendir $DIR2, catdir(IbexFarm->config->{deployment_dir}, $e)) {
                    close $DIR;
                    return $experiment_count_cache;
                }
                while (defined readdir($DIR2)) { ++$count; }
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
    $c->stash->{template} = "frontpage.tt";
}

sub bad_request :Path {
    my ($self, $c) = @_;
    $c->response->body('Bad request');
    $c->response->status(404);
}

sub default :Path {
    my ( $self, $c ) = @_;
    $c->response->body('Page not found');
    $c->response->status(404);
}

sub end : ActionClass('RenderView') {}

1;
