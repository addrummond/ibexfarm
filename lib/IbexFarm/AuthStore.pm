package IbexFarm::AuthStore;

# Code based on Catalyst::Authentication::Store::Minimal;

use strict;
use warnings;

use Catalyst::Authentication::User::Hash;
use File::Spec::Functions qw( splitdir catdir catfile splitpath no_upwards );
use JSON::XS;
use Digest;
use Crypt::Argon2;

{
    package MyUserHash;
    use base 'Catalyst::Authentication::User::Hash';

    sub check_password {
        my ($self, $password) = @_;

        if ($self->password =~ /^\$/) {
            # It's a new password.
            return Crypt::Argon2::argon2id_verify($self->password, $password);
        } else {
            # It's an old password.
            my $salt = substr($self->password, - IbexFarm->config->{user_password_salt_length});
            my $digest = Digest->new(IbexFarm->config->{user_password_hash_algo});
            $digest->add($password . $salt);
            my $b64 = $digest->b64digest;
            return $b64 eq substr($self->password, 0,
                                IbexFarm->config->{user_password_hash_total_length} - IbexFarm->config->{user_password_salt_length});
        }
    }
};

sub new {
    my $class = shift;
    bless { }, $class;
}

sub from_session {
    my ($self, $c, $id) = @_;

    return $id if ref $id;

    $self->find_user({ id => $id });
}

sub find_user {
    my ($self, $userinfo, $c) = @_;

    my $id = $userinfo->{id};
    $id ||= $userinfo->{username};

    my $udir = catdir(IbexFarm->config->{deployment_dir}, $id);
    return unless (-d $udir);

    my $ufile = catfile($udir, IbexFarm->config->{USER_FILE_NAME});
    die "User dir without '", IbexFarm->config->{USER_FILE_NAME}, "' file: $udir" unless (-f $ufile);
    open my $f, $ufile or die "Unable to open '", IbexFarm->config->{USER_FILE_NAME}, "' file: $!";
    local $/;
    my $contents = <$f>;
    my $coder = JSON::XS->new->boolean_values(\0, \1);
    my $json = $coder->decode($contents);
    die "Bad JSON in '", IbexFarm->config->{USER_FILE_NAME}, "' file" unless (ref($json) eq 'HASH');
    close $f or die "Unable to close '", IbexFarm->config->{USER_FILE_NAME}, "' file: $!";

    $json->{id} ||= $json->{username};
    $json->{username} ||= $json->{id};

    return MyUserHash->new(%$json);
}

1;
