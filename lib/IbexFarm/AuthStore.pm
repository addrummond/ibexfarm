package IbexFarm::AuthStore;

# Code based on Catalyst::Authentication::Store::Minimal;

use strict;
use warnings;

use Catalyst::Authentication::User::Hash;
use File::Spec::Functions qw( splitdir catdir catfile splitpath no_upwards );
use JSON::XS;
use Digest;

# Customized version of Catalyst::Authentication::User::Hash.
# (Yeah yeah, we really shouldn't need to override this method just to
# do simple salty password hashing, but there are crufty back compat issues
# with the old DBIx hashed passwords we have from when we were still using
# the postgres database. Yuck!)
{
    package MyUserHash;
    use base 'Catalyst::Authentication::User::Hash';

    sub check_password {
        my ($self, $password) = @_;

        my $salt = substr($self->password, - IbexFarm->config->{user_password_salt_length});
        my $digest = Digest->new(IbexFarm->config->{user_password_hash_algo});
        $digest->add($password . $salt);
        my $b64 = $digest->b64digest;
        return $b64 eq substr($self->password, 0,
                              IbexFarm->config->{user_password_hash_total_length} - IbexFarm->config->{user_password_salt_length});
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
    my $json = JSON::XS::decode_json($contents);
    die "Bad JSON in '", IbexFarm->config->{USER_FILE_NAME}, "' file" unless (ref($json) eq 'HASH');
    close $f or die "Unable to close '", IbexFarm->config->{USER_FILE_NAME}, "' file: $!";

    $json->{id} ||= $json->{username};
    $json->{username} ||= $json->{id};

    return MyUserHash->new(%$json);
}

1;
