package IbexFarm::Schema::Result::Role;

use strict;
use warnings;

use base 'DBIx::Class';

__PACKAGE__->load_components("InflateColumn::DateTime", "TimeStamp", "EncodedColumn", "Core");
__PACKAGE__->table("role");
__PACKAGE__->add_columns(
  "id",
  {
    data_type => "integer",
    default_value => "nextval('role_id_seq'::regclass)",
    is_nullable => 0,
    size => 4,
  },
  "role",
  {
    data_type => "character varying",
    default_value => undef,
    is_nullable => 0,
    size => undef,
  },
);
__PACKAGE__->set_primary_key("id");
__PACKAGE__->add_unique_constraint("role_pkey", ["id"]);
__PACKAGE__->has_many(
  "user_roles",
  "IbexFarm::Schema::Result::UserRole",
  { "foreign.role_id" => "self.id" },
);


# Created by DBIx::Class::Schema::Loader v0.04006 @ 2009-12-23 07:28:05
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:HtjTWTop2WbPdIMYDZRh+A


# You can replace this text with custom content, and it will be preserved on regeneration
1;
