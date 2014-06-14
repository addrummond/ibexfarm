package IbexFarm::CheckEmail;
use warnings;
use strict;

use parent 'Exporter';

sub is_ok_email {
    #
    # Original regex failed for some valid email addresses. Best just not to validate, since (as is well known)
    # there is no sensible way to check for the validity of an email address other than by sending an email to it.
    #
    return 1;
    #return shift =~ /^[a-z0-9!#$%&'*+\/=?^_`{|}~-]+(?:\.[a-z0-9!#$%&'*+\/=?^_`{|}~-]+)*@(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+(?:[A-Z]{2}|com|org|net|gov|edu|mil|biz|info|mobi|name|aero|jobs|museum)\b$/;
}

our @EXPORT = qw( is_ok_email );
