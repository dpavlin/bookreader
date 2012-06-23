#!/usr/bin/perl
use warnings;
use strict;

use Plack::Builder;
use Plack::Middleware::Debug;
use Plack::App::Directory;
use lib './lib';
use Plack::App::BookReader;

builder {

	enable 'Debug', panels => [
		qw(Environment Response Timer Memory),
	];

#	enable 'Plack::Middleware::Static',
#		path => qr{^/BookReader}, root => '../BookReader';

	enable 'StackTrace';

	mount '/BookReader' =>
		Plack::App::Directory->new({ root => "../BookReader" })->to_app;

	mount '/dk.nsk.hr' =>
		Plack::App::BookReader->new({ root => "/home/dpavlin/dk.nsk.hr" })->to_app;

}