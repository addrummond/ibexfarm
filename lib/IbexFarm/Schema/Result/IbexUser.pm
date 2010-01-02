package IbexFarm::Schema::Result::IbexUser;

use strict;
use warnings;

use base 'DBIx::Class';

__PACKAGE__->load_components("InflateColumn::DateTime", "TimeStamp", "EncodedColumn", "Core");
__PACKAGE__->table("ibex_user");
__PACKAGE__->add_columns(
  "id",
  {
    data_type => "integer",
    default_value => "nextval('ibex_user_id_seq'::regclass)",
    is_nullable => 0,
    size => 4,
  },
  "username",
  {
    data_type => "character varying",
    default_value => undef,
    is_nullable => 0,
    size => undef,
  },
  "password",
  {
    data_type => "character varying",
    default_value => undef,
    is_nullable => 0,
    size => undef,
  },
  "email_address",
  {
    data_type => "character varying",
    default_value => undef,
    is_nullable => 1,
    size => undef,
  },
  "active",
  { data_type => "boolean", default_value => undef, is_nullable => 0, size => 1 },
);
__PACKAGE__->set_primary_key("id");
__PACKAGE__->add_unique_constraint("ibex_user_pkey", ["id"]);
__PACKAGE__->has_many(
  "experiments",
  "IbexFarm::Schema::Result::Experiment",
  { "foreign.user_id" => "self.id" },
);
__PACKAGE__->has_many(
  "user_roles",
  "IbexFarm::Schema::Result::UserRole",
  { "foreign.user_id" => "self.id" },
);


# Created by DBIx::Class::Schema::Loader v0.04006 @ 2009-12-23 07:28:05
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:OsFfB7O9Rt415tnYjg3ulA

# NOTE: Spoiled checksum by changing 'is_nullable' to 1 for the email_address field of ibex_user.

__PACKAGE__->many_to_many(roles => 'user_roles', 'role');

__PACKAGE__->add_columns(
    'password' => {
        data_type           => "TEXT",
        size                => undef,
        encode_column       => 1,
        encode_class        => 'Digest',
        encode_args         => { salt_length => 32, algorithm => "SHA-512", format => 'base64' },
        encode_check_method => 'check_password',
    },
);

# You can replace this text with custom content, and it will be preserved on regeneration
1;
