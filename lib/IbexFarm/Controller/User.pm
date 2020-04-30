package IbexFarm::Controller::User;

use strict;
use warnings;
use parent 'Catalyst::Controller';
use File::Spec::Functions qw( catfile catdir );
use IbexFarm::FNames;
use IbexFarm::CheckEmail;
use File::Path qw( rmtree );
use Digest;
use IbexFarm::Util qw( log_event );
use Net::SSLeay;
use Crypt::Argon2;

my $get_salt = sub {
    my $length = shift;
    my @salt_pool = ('A' .. 'Z', 'a' .. 'z', 0 .. 9, '+','/','=');
    my $salt_pool_length = 26 * 2 + 10 + 3;
    my $rb = '';
    Net::SSLeay::RAND_bytes($rb, $length);
    my $out = '';
    for (my $i = 0; $i < $length; ++$i) {
        $out .= $salt_pool[ord(substr($rb, $i, $i+1)) % $salt_pool_length];
    }
    return $out;
};

my $make_pw_hash = sub {
    my $password = shift;
    my $salt = $get_salt->(IbexFarm->config->{argon2id_salt_length});
    return Crypt::Argon2::argon2id_pass(
        $password,
        $salt,
        IbexFarm->config->{argon2id_t_cost},
        IbexFarm->config->{argon2id_m_factor},
        IbexFarm->config->{argon2id_parallelism},
        IbexFarm->config->{argon2id_tag_size},
    );
};

sub login :Absolute :Args(0) {
    my ($self, $c) = @_;

    my $username = $c->request->params->{username};
    my $password = $c->request->params->{password};

    if ($username && $password) {
        if ($c->authenticate({ username => $username, password => $password })) {
            log_event("User $username logged in.");

            IbexFarm::Util::update_json_file(
                catfile(IbexFarm->config->{deployment_dir}, $username, IbexFarm->config->{USER_FILE_NAME}),
                sub {
                    my $j = shift;
                    if (IbexFarm->config->{rehash_old_passwords} && $j->{password} !~ /^\$/) {
                        # Rehash the password using a modern pw hash.
                        log_event("Rehashing password for user $username.");
                        $j->{password} = $make_pw_hash->($password);
                        return $j;
                    } else {
                        return undef; # leave the file unmodified
                    }
                }
            );

            $c->response->redirect($c->uri_for('/myaccount'));
        }
        else {
            log_event("User $username FAILED to log in.");
            $c->stash->{username} = $username;
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
        # Delete the user's dir, and www dir if any.
        # Note that the www dir will not exist (whatever the value of 'deployment_www_dir')
        # if the user has never created an experiment).
        my @dirs = catdir(IbexFarm->config->{deployment_dir}, $c->user->username);
        my $www = catdir(IbexFarm->config->{deployment_www_dir}, $c->user->username);
        push @dirs, $www if (IbexFarm->config->{deployment_www_dir} && -d $www);
        my $r = rmtree(\@dirs, 0, 0);
        unless ($r) {
            die "Inconsistency when deleting user account!";
        }

        log_event("User " . $c->user->username . " deleted.");

        my $username = $c->user->username;
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
            IbexFarm::Util::update_json_file(
                catfile(IbexFarm->config->{deployment_dir}, $c->user->username, IbexFarm->config->{USER_FILE_NAME}),
                sub {
                    my $j = shift;
                    $j->{email_address} = $c->req->params->{email};
                    return $j;
                }
            );

            $c->stash->{email_address} = $c->req->params->{email};
            $c->stash->{message} = "Your email has been updated.";
            $c->stash->{template} = "user.tt";
        }
    }
}

sub update_password :Absolute :Args(0) {
    my ($self, $c) = @_;

    $c->detach('Root', 'bad_request') unless (defined $c->req->params->{password1} && defined $c->req->params->{password2});

    if (! $c->user_exists) {
        $c->stash->{error} = "You must be logged in to change your password.";
        $c->stash->{template} = "login.tt";
        return;
    }

    my $password1 = $c->request->params->{password1};
    my $password2 = $c->request->params->{password2};

    if (! $password1 || ! $password2) {
        $c->stash->{error} = "You must fill in both password fields.";
        $c->stash->{template} = "user.tt";
        return;
    }
    if ($password1 ne $password2) {
        $c->stash->{error} = "The passwords do not match.";
        $c->stash->{template} = "user.tt";
        return;
    }

    my $pwhash = $make_pw_hash->($password1);
    IbexFarm::Util::update_json_file(
        catfile(IbexFarm->config->{deployment_dir}, $c->user->username, IbexFarm->config->{USER_FILE_NAME}),
        sub {
            my $j = shift;
            $j->{password} = $pwhash;
            return $j;
        }
    );

    $c->stash->{message} = "Your password has been updated. Use the new password next time you log in.";
    $c->stash->{template} = "user.tt";
}

sub newaccount :Absolute :Args(0) {
    my ($self, $c) = @_;

    my $username = $c->request->params->{username};
    my $password = $c->request->params->{password};
    my $password2 = $c->request->params->{password2};
    my $email = $c->request->params->{email};

    my $stash_user_info = sub {
        $c->stash->{username} = $username;
        $c->stash->{email} = $email;
    };

    my $ispost = $c->req->method eq "POST";

    if ($ispost && (! ($username && $password && $password2))) {
        $c->stash->{error} = "You must fill in all the fields except email.";
        $c->stash->{template} = "newaccount.tt";
        $stash_user_info->();
    }
    elsif ($ispost && (! IbexFarm::FNames::is_ok_fname($username))) {
        $c->stash->{error} = "Usernames may contain only " . IbexFarm::FNames::OK_CHARS_DESCRIPTION . "and must be less than " . IbexFarm->config->{max_fname_length} . " characters long.";
        $c->stash->{template} = "newaccount.tt";
        $stash_user_info->();
    }
    elsif ($ispost && ($password ne $password2)) {
        $c->stash->{error} = "The passwords do not match.";
        $c->stash->{template} = "newaccount.tt";
        $stash_user_info->();
    }
    elsif ($ispost && ($email && (! IbexFarm::CheckEmail::is_ok_email($email)))) {
        $c->stash->{error} = "The email address you entered is not valid. (Note that you don't have to give an email if you don't want to.)";
        $c->stash->{template} = "newaccount.tt";
        $stash_user_info->();
    }
    elsif (! $ispost) {
        $c->stash->{template} = "newaccount.tt";
    }
    else {
        # Check that a user with that username doesn't already exist.
        my $udir = catdir(IbexFarm->config->{deployment_dir}, $username);
        if (-e $udir) {
            $c->stash->{username} = $username;
            $c->stash->{email} = $email;
            $c->stash->{error} = "An account with that username already exists.";
            $c->stash->{template} = "newaccount.tt";
        }
        else {
            # Log the user out, if one is logged in.
            $c->logout if ($c->user_exists);

            my $pwhash = $make_pw_hash->($password);

            my $user = {
                username => $username,
                password => $pwhash,
                email_address => $email || undef,
                active => 1,
                user_roles => [ 'user' ]
            };

            # Create the user's dir.
            eval {
                mkdir $udir or die "Unable to create dir for user: $!";

                # Write the user info to the 'USER' file.
                open my $f, '>' . catfile($udir, IbexFarm->config->{USER_FILE_NAME}) or die "Unable to open '", IbexFarm->config->{USER_FILE_NAME}, "' file: $!";
                print $f JSON::XS::encode_json($user);
                close $f;
            };
            if ($@) {
                if (-d $udir) { rmdir $udir or die "Unable to remove user directory following error."; }
                die $@;
            }

            $c->authenticate({ username => $username, password => $password }) or
                die "Unable to authenticate following account creation.";

            log_event("User account $username created.");

            $c->response->redirect($c->uri_for('/myaccount'));
        }
    }
}

sub myaccount :Absolute :Args(0) {
    my ($self, $c) = @_;

    return $c->response->redirect($c->uri_for('/login')) unless ($c->user_exists);

    my $ufile = catdir(IbexFarm->config->{deployment_dir}, $c->user->username, IbexFarm->config->{USER_FILE_NAME});
    open my $f, $ufile or die "Unable to open '", IbexFarm->config->{USER_FILE_NAME}, "' file for reading.";
    local $/;
    my $contents = <$f>;
    close $f or die "Unable to close '", IbexFarm->config->{USER_FILE_NAME}, "' file after reading.";
    my $coder = JSON::XS->new->boolean_values(\0, \1);
    my $u = $coder->decode($contents);
    die "Bad JSON for user" unless (ref($u) eq 'HASH');

    $c->stash->{email_address} = $u->{email_address};
    $c->stash->{template} = 'user.tt';
}

sub logout :Absolute :Args(0) {
    my ($self, $c) = @_;

    my $username = $c->user->username;
    $c->logout;
    log_event("User $username logged out.");
    $c->response->redirect($c->uri_for('/'));
}

1;
