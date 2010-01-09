package IbexFarm::Controller::Experiment;

use strict;
use warnings;
use parent 'Catalyst::Controller';

sub manage :Absolute {
    my ($self, $c, $experiment) = (shift, shift, shift);
    return $c->res->redirect($c->uri_for('/login')) unless $c->user_exists;
    return $c->res->redirect($c->uri_for('/myaccount')) unless $experiment;
    $c->detach('Root', 'default') if scalar(@_);

    $c->stash->{experiment_base_url} = IbexFarm->config->{experiment_base_url};
    $c->stash->{experiment} = $experiment;
    $c->stash->{template} = "manage.tt";
}

1;
