package Catalyst::Plugin::UploadEnforcer;
use warnings;
use strict;

# Note: this plugin is very specific to this application
# (it knows how upload request URLs are formatted).

use Catalyst::Request;
use IbexFarm;
use IbexFarm::FNames;
use IbexFarm::AjaxHeaders qw( ajax_headers );
use HTML::GenerateUtil qw( escape_html );
use NEXT;
use YAML;

sub dispatch {
    my $c = shift;

    if ($c->req->path =~ /^ajax\/+upload_file\/+/) {
        my @args = $c->req->arguments;
#        print STDERR "\n\n\n", YAML::Dump(\@args), YAML::Dump($c->req->upload('userfile')), "  ", scalar(@{$args[0]}), "\n\n";
        if (scalar(@{$args[0]}) == 2 && $c->req->upload('userfile') && ! IbexFarm::FNames::is_ok_fname($c->req->upload('userfile')->filename)) {
            print STDERR "\n\nNOOOOOOOOOOOOOOOOOOOO\n\n";
            ajax_headers($c, 'text/html', 'UTF-8');
            return $c->res->body('Filenames may contain only ' . escape_html(IbexFarm::FNames::OK_CHARS_DESCRIPTION));
        }
        elsif ($c->req->upload('userfile') && $c->req->upload('userfile')->size > IbexFarm->config->{max_upload_size_bytes}) {
            ajax_headers($c, 'text/html', 'UTF-8');
            return $c->res->body('The file is too large (maximum size is ' . sprintf("%.1f", IbexFarm->config->{max_upload_size_bytes}/1024.0/1024.0) . " MB).");
        }
    }

    return $c->NEXT::ACTUAL::dispatch(@_);
}

1;
