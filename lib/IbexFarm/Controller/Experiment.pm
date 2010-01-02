package IbexFarm::Controller::Experiment;

use strict;
use warnings;
use parent 'Catalyst::Controller';

sub manage :Absolute {
    my ($self, $c, $experiment) = (shift, shift, shift);
    $c->res->redirect('/login') unless $c->user_exists;
    $c->detach('default') unless $experiment && (! scalar(@_));

    $c->stash->{experiment} = $experiment;
    $c->stash->{template} = "manage.tt";
}

1;
