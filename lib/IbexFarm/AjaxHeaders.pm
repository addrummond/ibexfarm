package IbexFarm::AjaxHeaders;
use warnings;
use strict;

use base 'Exporter';

our @EXPORT_OK = qw( ajax_headers );

sub ajax_headers {
    my ($c, $content_type, $encoding, $code) = @_;
    $code //= 200;

    $c->res->code($code);
    $c->res->content_type($content_type);
    $c->res->content_encoding($encoding);
    $c->res->headers->header(Pragma => 'no-cache');
    $c->res->headers->header(Expires => 'Thu, 01 Jan 1970 00:00:00 GMT');
    $c->res->headers->header('Cache-Control' => 'no-store, no-cache, must-revalidate, post-check=0, pre-check=0');
}

1;
