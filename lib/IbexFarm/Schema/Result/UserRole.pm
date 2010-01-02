package IbexFarm::Schema::Result::UserRole;

use strict;
use warnings;

use base 'DBIx::Class';

__PACKAGE__->load_components("InflateColumn::DateTime", "TimeStamp", "EncodedColumn", "Core");
__PACKAGE__->table("user_role");
__PACKAGE__->add_columns(
  "user_id",
  { data_type => "integer", default_value => undef, is_nullable => 0, size => 4 },
  "role_id",
  { data_type => "integer", default_value => undef, is_nullable => 0, size => 4 },
);
__PACKAGE__->set_primary_key("user_id", "role_id");
__PACKAGE__->add_unique_constraint("user_role_pkey", ["user_id", "role_id"]);
__PACKAGE__->belongs_to(
  "user_id",
  "IbexFarm::Schema::Result::IbexUser",
  { id => "user_id" },
);
__PACKAGE__->belongs_to(
  "role_id",
  "IbexFarm::Schema::Result::Role",
  { id => "role_id" },
);


# Created by DBIx::Class::Schema::Loader v0.04006 @ 2009-12-23 07:28:05
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:TCHl8tQGz6PBCTNqCpXfaA


# You can replace this text with custom content, and it will be preserved on regeneration
1;
