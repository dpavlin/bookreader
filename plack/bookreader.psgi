#!/usr/bin/perl
use warnings;
use strict;

use Plack::Builder;
use Plack::Middleware::Debug;
use Plack::App::Directory;
use lib './lib';
use Plack::App::BookReader;

builder {

	# use proxy headers for client IP address
	enable sub {
		my ( $app, $env ) = @_;
		return sub {
			my $env = shift;
			my $client_ip = $env->{HTTP_X_REAL_IP} || $env->{HTTP_X_FORWARDED_FOR};
			if ( $client_ip ) {
				my $proxy_ip = $env->{REMOTE_ADDR};
				die "request not from authorized proxy $proxy_ip" if $proxy_ip !~ /\Q127.0.0.1\E$/;
				warn "# rewrite $proxy_ip -> $client_ip\n";
				$env->{REMOTE_ADDR} = $client_ip;
			}

			$app->( $env );
		}
	};

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

	mount '/jstore' =>
		Plack::App::BookReader->new({ root => "/mnt/jstore" })->to_app;

}
