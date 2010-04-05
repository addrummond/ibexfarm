package IbexFarm;

use strict;
use warnings;

use Catalyst::Runtime 5.80;

# Set flags and add plugins for the application
#
#         -Debug: activates the debug mode for very useful log messages
#   ConfigLoader: will load the configuration from a Config::General file in the
#                 application's home directory
# Static::Simple: will serve static files from the application's root
#                 directory

use parent qw/Catalyst/;
use Catalyst qw/ConfigLoader

                Authentication
                Authentication::Credential::Password

                Session
                Session::Store::FastMmap
                Session::State::Cookie

                Cache::FastMmap
                UploadProgress
                /;
use IbexFarm::AuthStore;
our $VERSION = '0.01';

# Configure the application.
#
# Note that settings in ibexfarm.conf (or other external
# configuration file that you set up manually) take precedence
# over this when using ConfigLoader. Thus configuration
# details given here can function as a default configuration,
# with an external configuration file acting as an override for
# local deployment.

__PACKAGE__->config(
    parse_on_demand => 1,
    name => 'IbexFarm',
    default_view => 'TT',
    'Plugin::Authentication' => {
        default_realm => 'users',
        realms => {
            users => {
                credential => {
                    class => 'Password',
                    password_field => 'password',
                    # Weird mismatches between behavior of DBIx::Class::EncodedColumn and Crypt::SaltedHash
                    # force us to do this manually.
                    password_type => 'self_check',
#                    password_type => 'salted_hash',
#                    password_hash_type => 'SHA-512',
#                    password_salt_len => 32
                },
                store => {
                    class => '+IbexFarm::AuthStore',
                    user_model => 'Catalyst::Authentication::User::Hash',
                    password_type => 'clear',
                }
           }
       }
    },
    USER_FILE_NAME => 'USER',

    user_password_hash_algo => 'SHA-512',
    user_password_salt_length => 32,
    user_password_hash_total_length => 118
);

# Start the application
my @args;
push @args, 'Static::Simple' if ($ENV{STATIC});
__PACKAGE__->setup(@args);

=head1 NAME

IbexFarm - Catalyst based application

=head1 SYNOPSIS

    script/ibexfarm_server.pl

=head1 DESCRIPTION

[enter your description here]

=head1 SEE ALSO

L<IbexFarm::Controller::Root>, L<Catalyst>

=head1 AUTHOR

Alex Drummond

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
