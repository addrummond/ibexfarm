package IbexFarm::Controller::User;

use strict;
use warnings;
use parent 'Catalyst::Controller';
use File::Spec::Functions qw( catfile catdir );
use IbexFarm::FNames;
use IbexFarm::CheckEmail;
use File::Path qw( rmtree );
use YAML;

sub login :Absolute :Args(0) {
    my ($self, $c) = @_;

    my $username = $c->request->params->{username};
    my $password = $c->request->params->{password};

    if ($username && $password) {
        if ($c->authenticate({ username => $username, password => $password })) {
            $c->response->redirect($c->uri_for('/myaccount'));
        }
        else {
            $c->stash->{error} = "The details you entered were not recognized.";
            $c->stash->{template} = "login.tt";
        }
    }
    else {
        $c->stash->{template} = "login.tt";
    }
}

sub delete_account :Absolute :Args(0) {
    my ($self, $c) = @_;

    if (! $c->user_exists) {
        $c->stash->{error} = "You must be logged in to delete your account.";
        $c->stash->{template} = "login.tt";
    }
    elsif ($c->req->method eq "GET") {
        $c->stash->{template} = "delete_account.tt";
    }
    elsif ($c->req->method eq "POST") {
        $c->model('DB::IbexUser')->search({ username => $c->user->username })->delete;
        $c->model('DB')->txn_commit;

        # Now delete the user's dir, and ww dir if any.
        # Note that the www dir will not exist (whatever the value of 'deployment_www_dir')
        # if the user has never created an experiment).
        my @dirs = catdir(IbexFarm->config->{deployment_dir}, $c->user->username);
        my $www = catdir(IbexFarm->config->{deployment_www_dir}, $c->user->username);
        push @dirs, $www if (IbexFarm->config->{deployment_www_dir} && -d $www);
        my $r = rmtree(\@dirs, 0, 0);
        unless ($r) {
            die "Inconsistency when deleting user account!";
        }

        $c->logout;

        $c->stash->{template} = "deleted.tt";
    }
    else {
        $c->detach('Root', 'bad_request');
    }
}

sub update_email :Absolute :Args(0) {
    my ($self, $c) = @_;

    $c->detach('Root', 'bad_request') unless defined $c->req->params->{email};

    if (! $c->user_exists) {
        $c->stash->{error} = "You must be logged in to update your email.";
        $c->stash->{template} = "login.tt";
    }
    else {
        if ($c->req->params->{email} && ! IbexFarm::CheckEmail::is_ok_email($c->req->params->{email})) {
            $c->stash->{error} = "The email address you entered is not valid.";
            $c->stash->{template} = 'user.tt';
        }
        else {
            my $u = $c->model('DB::IbexUser')->find({ id => $c->user->id }) or die "Oh no";
            $u->update({ 'email_address' =>  $c->req->params->{email} }) or die "Oh no 2";
            $c->model('DB')->txn_commit;
            $c->stash->{email_address} = $c->req->params->{email};
            $c->stash->{message} = "Your email has been updated.";
            $c->stash->{template} = 'user.tt';
        }
    }
}

sub newaccount :Absolute :Args(0) {
    my ($self, $c) = @_;

    my $username = $c->request->params->{username};
    my $password = $c->request->params->{password};
    my $email = $c->request->params->{email};

    if (! $username) {
        $c->stash->{template} = "newaccount.tt";
        return;
    }

    if (! IbexFarm::FNames::is_ok_fname($username)) {
        $c->stash->{error} = "Usernames may contain only " . IbexFarm::FNames::OK_CHARS_DESCRIPTION . ".";
        $c->stash->{template} = "newaccount.tt";
    }
    elsif ($email && (! IbexFarm::CheckEmail::is_ok_email($email))) {
        $c->stash->{error} = "The email address you entered is not valid. (Note that you don't have to give an email if you don't want to.)";
        $c->stash->{template} = "newaccount.tt";
    }
    elsif (! ($username && $password)) {
        $c->stash->{template} = "newaccount.tt";
    }
    else {
        # It had better be a post request if they're trying to create a new account.
        $c->detach('Root', 'bad_request') unless ($c->req->method eq "POST");

        # Check that a user with that username doesn't already exist.
        if ($c->model('DB::IbexUser')->find({ username => $username })) {
            $c->stash->{error} = "An account with that username already exists.";
            $c->stash->{template} = "newaccount.tt";
        }
        else {
            # Add the new user to the database, create their dir, and then show the login form.
            $c->model('DB')->txn_do(sub {
                my $r = $c->model('DB::Role')->find({ role => "user" });

                $c->model('DB::IbexUser')->create({
                    username => $username,
                    password => $password,
                    email_address => $email || undef,
                    active => 1,
                    experiments => [],
                    user_roles => [ { role_id => $r } ] # Note that this will error out if $r is undef (which is what we want).
                });

                $c->model('DB')->txn_commit(); # This should be redundant, but doesn't seem to be.

                # Create the user's dir.
                mkdir catdir(IbexFarm->config->{deployment_dir}, $username) or die "Unable to create dir for user: $!";
            });

            $c->stash->{login_msg} = "Your account was created; you may now log in.";
            $c->stash->{username} = $c->request->params->{username};
            undef $c->request->params->{username};
            undef $c->request->params->{password};
            $c->detach('login');
#           $c->response->redirect($c->uri_for('/login'));
        }
    }
}

sub myaccount :Absolute :Args(0) {
    my ($self, $c) = @_;

    return $c->response->redirect($c->uri_for('/login')) unless ($c->user_exists);

    my $u = $c->model('DB::IbexUser')->find({ id => $c->user->id }) or die "Oh no 3";
    $c->stash->{email_address} = $u->email_address;
    $c->stash->{template} = 'user.tt';
}

sub logout :Absolute :Args(0) {
    my ($self, $c) = @_;

    $c->logout;
    $c->response->redirect($c->uri_for('/'));
}

1;
