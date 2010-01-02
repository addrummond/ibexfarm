package IbexFarm::Controller::Root;

use strict;
use warnings;
use parent 'Catalyst::Controller';

#
# Sets the actions in this controller to be registered with no prefix
# so they function identically to actions created in MyApp.pm
#
__PACKAGE__->config->{namespace} = '';

sub index :Path :Args(0) {
    my ( $self, $c ) = @_;

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
