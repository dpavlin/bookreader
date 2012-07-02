#!/usr/bin/perl
use warnings;
use strict;

use Plack::Builder;
use Plack::Middleware::Debug;
use Plack::App::Directory;
use lib './lib';
use Plack::App::BookReader;

builder {

	enable "Plack::Middleware::ServerStatus::Lite",
		path => '/server-status',
#		allow => [ '127.0.0.1', '10.60.0.0/16', '193.198.0.0/16', '0.0.0.0/32' ], # FIXME doesn't work for IPv6
		counter_file => '/tmp/counter_file',
		scoreboard => '/tmp/server-status';

	enable 'Debug', panels => [
		qw(Environment Response Timer Memory),
	];

#	enable 'Plack::Middleware::Static',
#		path => qr{^/BookReader}, root => '../BookReader';

	enable 'StackTrace';

	enable "ConditionalGET";
	enable "Plack::Middleware::ETag", file_etag => [ "inode", "size", "mtime" ];

	mount '/BookReader' =>
		Plack::App::Directory->new({ root => "../BookReader" })->to_app;

	mount '/cache/' =>
		Plack::App::BookReader->new({ root => "cache" })->to_app;

	# resouces

	mount '/dk.nsk.hr' =>
		Plack::App::BookReader->new({ root => "/srv/dk.nsk.hr" })->to_app;

	mount '/share' =>
		Plack::App::BookReader->new({ root => "/mnt/share" })->to_app;

	mount '/NSK' =>
		Plack::App::Directory->new({ root => "NSK" })->to_app;

}
