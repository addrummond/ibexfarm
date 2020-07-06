use strict;
use warnings;
use IbexFarm;
use Net::SSLeay;
use Crypt::Argon2;
use File::Spec::Functions qw( catfile );

if (scalar(@ARGV) < 1 || scalar(@ARGV) > 2) {
    print STDERR "Bad usage: pass username as first argument, password as optional second argument.\n";
    exit 1
}

my $username = $ARGV[0];
my $user_file = catfile(IbexFarm->config->{deployment_dir}, $username, IbexFarm->config->{USER_FILE_NAME});

if (! -f $user_file) {
    print STDERR "User '$username' not found.\n";
    exit 1
}

sub get_salt {
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

sub get_random_password {
    my $length = 16;
    my @pool = ('A' .. 'Z', 'a' .. 'z', 0 .. 9);
    my $pool_length = 26 * 2 + 10;
    my $rb = '';
    Net::SSLeay::RAND_bytes($rb, $length);
    my $out = '';
    for (my $i = 0; $i < $length; ++$i) {
        $out .= $pool[ord(substr($rb, $i, $i+1)) % $pool_length];
    }
    return $out;
}

sub make_pw_hash {
    my $password = shift;
    my $salt = get_salt(IbexFarm->config->{argon2id_salt_length});
    return Crypt::Argon2::argon2id_pass(
        $password,
        $salt,
        IbexFarm->config->{argon2id_t_cost},
        IbexFarm->config->{argon2id_m_factor},
        IbexFarm->config->{argon2id_parallelism},
        IbexFarm->config->{argon2id_tag_size},
    );
}

my $newpw;
if (scalar(@ARGV) == 1) {
    $newpw = get_random_password();
} else {
    $newpw = $ARGV[1];
}
my $newpwhash = make_pw_hash($newpw);

IbexFarm::Util::update_json_file(
    $user_file,
    sub {
        my $j = shift;
        $j->{password} = $newpwhash;
        return $j;
    }
);

print "The password for user '$username' has been reset to:\n$newpw\n";