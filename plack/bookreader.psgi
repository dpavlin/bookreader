#!/usr/bin/perl
use warnings;
use strict;

use Plack::Builder;
use Plack::App::Directory;
use Plack::Middleware::Debug;


builder {

	enable 'Debug', panels => [
		qw(Environment Response Timer Memory),
	];

#	enable 'Plack::Middleware::Static',
#		path => qr{^/BookReader}, root => '../BookReader';

	enable 'StackTrace';

	mount '/BookReader' =>
		Plack::App::Directory->new({ root => "../BookReader" })->to_app;

	mount '/BookReaderDemo' =>
		Plack::App::Directory->new({ root => "../BookReaderDemo" })->to_app;

}
