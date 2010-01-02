#!/usr/bin/env perl
# IMPORTANT: if you delete this file your app will not work as
# expected.  You have been warned.
use inc::Module::Install;

name 'IbexFarm';
all_from 'lib/IbexFarm.pm';

requires 'Catalyst::Runtime' => '5.80014';
requires 'Catalyst::Plugin::ConfigLoader';
requires 'Catalyst::Plugin::Static::Simple';
requires 'Catalyst::Action::RenderView';
requires 'parent';
requires 'Config::General'; # This should reflect the config file format you've chosen
                 # See Catalyst::Plugin::ConfigLoader for supported formats

requires 'Catalyst::Plugin::Authentication';
requires 'Catalyst::Plugin::Session';
requires 'Catalyst::Plugin::Session::Store::FastMmap';
requires 'Catalyst::Plugin::Session::State::Cookie';
requires 'Catalyst::Plugin::RequireSSL';
requires 'Catalyst::Plugin::UploadProgress';
#requires 'Authentication::Store::Minimal';

catalyst;

install_script glob('script/*.pl');
auto_install;
WriteAll;
