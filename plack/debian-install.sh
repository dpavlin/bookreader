#!/bin/sh -xe

sudo apt-get install libplack-perl starman cpanminus \
	libfile-slurp-perl libjson-perl libjson-xs-perl \
	libnet-cidr-lite-perl \
	libnet-netmask-perl libregexp-common-perl \
	graphicsmagick libgraphics-magick-perl \
	poppler-utils

cpanm --sudo Plack::Middleware::Debug Plack::Middleware::ETag  Plack::Middleware::ServerStatus::Lite  Plack::Middleware::XForwardedFor
