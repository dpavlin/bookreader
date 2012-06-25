#!/bin/sh -xe

sudo apt-get install libplack-perl starman cpanminus \
	libfile-slurp-perl libjson-perl libjson-xs-perl \
	graphicsmagick libgraphics-magick-perl \
	poppler-utils

cpanm --sudo Plack::Middleware::Debug Plack::Middleware::ETag
