package Plack::App::BookReader;
use parent qw(Plack::App::File);
use strict;
use warnings;
use Plack::Util;
use HTTP::Date;
use Plack::MIME;
use DirHandle;
use URI::Escape;
use Plack::Request;
use Data::Dump qw(dump);
use File::Path qw(make_path remove_tree);
use Graphics::Magick;
use File::Slurp;
use JSON;
use Time::Piece ();
use Time::Seconds 'ONE_YEAR';
use autodie;

sub make_basedir {
	my $path = shift;
	return if -e $path;
	$path =~ s{/[^/]+$}{} || die "no dir/file in $path";
	File::Path::make_path $path;
}

# Stolen from rack/directory.rb
my $dir_file = "<tr><td class='name'><a href='%s'>%s</a></td><td class='size'>%s</td><td class='type'>%s</td><td class='mtime'>%s</td></tr>";
my $dir_page = <<PAGE;
<html><head>
  <title>%s</title>
  <meta http-equiv="content-type" content="text/html; charset=utf-8" />
  <style type='text/css'>
table { width:100%%; }
.name { text-align:left; }
.size, .mtime { text-align:right; }
.type { width:11em; }
.mtime { width:15em; }
  </style>
</head><body>
<h1>%s</h1>
<hr />
<table>
  <tr>
    <th class='name'>Name</th>
    <th class='size'>Size</th>
    <th class='type'>Type</th>
    <th class='mtime'>Last Modified</th>
  </tr>
%s
</table>
<hr />
<code>%s</code>
</body></html>
PAGE

my $reader_page = <<'PAGE';
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01//EN" "http://www.w3.org/TR/html4/strict.dtd">
<html>
<head>
    <title>%s</title>
    
    <link rel="stylesheet" type="text/css" href="/BookReader/BookReader.css"/>
    <script type="text/javascript" src="http://www.archive.org/includes/jquery-1.4.2.min.js"></script>
    <script type="text/javascript" src="http://www.archive.org/bookreader/jquery-ui-1.8.5.custom.min.js"></script>

    <script type="text/javascript" src="http://www.archive.org/bookreader/dragscrollable.js"></script>
    <script type="text/javascript" src="http://www.archive.org/bookreader/jquery.colorbox-min.js"></script>
    <script type="text/javascript" src="http://www.archive.org/bookreader/jquery.ui.ipad.js"></script>
    <script type="text/javascript" src="http://www.archive.org/bookreader/jquery.bt.min.js"></script>

    <script type="text/javascript" src="/BookReader/BookReader.js"></script>

<style type="text/css">

/* Hide print and embed functionality */
#BRtoolbar .embed, .print {
    display: none;
}

</style>

<script type="text/javascript">
$(document).ready( function() {

// 
// This file shows the minimum you need to provide to BookReader to display a book
//
// Copyright(c)2008-2009 Internet Archive. Software license AGPL version 3.

// Create the BookReader object
var br = new BookReader();

var pages = %s;

// Return the width of a given page.  Here we assume all images are 800 pixels wide
br.getPageWidth = function(index) {
	if ( ! pages[index] ) return;
    return parseInt( pages[index][1] );
}

// Return the height of a given page.  Here we assume all images are 1200 pixels high
br.getPageHeight = function(index) {
	if ( ! pages[index] ) return;
    return parseInt( pages[index][2] );
}

// We load the images from archive.org -- you can modify this function to retrieve images
// using a different URL structure
br.getPageURI = function(index, reduce, rotate) {
	if ( ! pages[index] ) return;
    // reduce and rotate are ignored in this simple implementation, but we
    // could e.g. look at reduce and load images from a different directory
    // or pass the information to an image server
	var url = pages[index][0] + '?reduce='+reduce;
	console.debug('getPageURI', index, reduce, rotate, url);
    return url;
}

// Return which side, left or right, that a given page should be displayed on
br.getPageSide = function(index) {
    if (0 == (index & 0x1)) {
        return 'R';
    } else {
        return 'L';
    }
}

// This function returns the left and right indices for the user-visible
// spread that contains the given index.  The return values may be
// null if there is no facing page or the index is invalid.
br.getSpreadIndices = function(pindex) {   
    var spreadIndices = [null, null]; 
    if ('rl' == this.pageProgression) {
        // Right to Left
        if (this.getPageSide(pindex) == 'R') {
            spreadIndices[1] = pindex;
            spreadIndices[0] = pindex + 1;
        } else {
            // Given index was LHS
            spreadIndices[0] = pindex;
            spreadIndices[1] = pindex - 1;
        }
    } else {
        // Left to right
        if (this.getPageSide(pindex) == 'L') {
            spreadIndices[0] = pindex;
            spreadIndices[1] = pindex + 1;
        } else {
            // Given index was RHS
            spreadIndices[1] = pindex;
            spreadIndices[0] = pindex - 1;
        }
    }
    
    return spreadIndices;
}

// For a given "accessible page index" return the page number in the book.
//
// For example, index 5 might correspond to "Page 1" if there is front matter such
// as a title page and table of contents.
br.getPageNum = function(index) {
    return index+1;
}

// Total number of leafs
br.numLeafs = pages.length;

// Book title and the URL used for the book title link
br.bookTitle= '%s';
br.bookUrl  = '%s';

// Override the path used to find UI images
br.imagesBaseURL = '/BookReader/images/';

br.getEmbedCode = function(frameWidth, frameHeight, viewParams) {
    return "Embed code not supported in bookreader demo.";
}

// Let's go!
br.init();

// read-aloud and search need backend compenents and are not supported in the demo
$('#BRtoolbar').find('.read').hide();
$('#textSrch').hide();
$('#btnSrch').hide();

} );
</script>

</head>
<body style="background-color: ##939598;">

<div id="BookReader">
    Internet Archive BookReader<br/>
    
    <noscript>
    <p>
        The BookReader requires JavaScript to be enabled. Please check that your browser supports JavaScript and that it is enabled in the browser settings.
    </p>
    </noscript>
</div>


</body>
</html>
PAGE

sub should_handle {
    my($self, $file) = @_;
    return -d $file || -f $file;
}

sub return_dir_redirect {
    my ($self, $env) = @_;
    my $uri = Plack::Request->new($env)->uri;
    return [ 301,
        [
            'Location' => $uri . '/',
            'Content-Type' => 'text/plain',
            'Content-Length' => 8,
        ],
        [ 'Redirect' ],
    ];
}

sub serve_path {
    my($self, $env, $path, $fullpath) = @_;

	my $req = Plack::Request->new($env);

    my $dir_url = $env->{SCRIPT_NAME} . $env->{PATH_INFO};

    if (-f $path) {

		if ( my $reduce = $req->param('reduce') ) {
			$reduce = int($reduce); # BookReader javascript somethimes returns float
			warn "# reduce $reduce $path\n";

			my $cache_path = "cache/$dir_url.reduce.$reduce.jpg";
			if ( $reduce <= 1 && $path =~ m/\.jpe?g$/ ) {
				$cache_path = $path;
			} elsif ( ! -e $cache_path ) {
				my $image = Graphics::Magick->new;
				warn "## Read $path ", -s $path, " bytes\n";
				$image->Read($path);
				my ( $w, $h ) = $image->Get('width','height');
				$image->Resize(
					width  => $w / $reduce,
					height => $h / $reduce
				);
				make_basedir $cache_path;
				$image->Write( filename => $cache_path );
				warn "# created $cache_path ", -s $cache_path, " bytes\n";
			}

        	return $self->SUPER::serve_path($env, $cache_path, $fullpath);

		}

        return $self->SUPER::serve_path($env, $path, $fullpath);
    }

    if ($dir_url !~ m{/$}) {
        return $self->return_dir_redirect($env);
    }

    my @files = ();

    my $dh = DirHandle->new($path);
    my @children;
    while (defined(my $ent = $dh->read)) {
        next if $ent eq '.';
        push @children, $ent;
    }

	my @page_files;

    for my $basename (sort { $a cmp $b } @children) {
		push @page_files, $basename if $basename =~ m/\d+\.(jpg|gif|pdf)$/;
        my $file = "$path/$basename";
        my $url = $dir_url . $basename;

        my $is_dir = -d $file;
        my @stat = stat _;


        $url = join '/', map {uri_escape($_)} split m{/}, $url;

        if ($is_dir) {
            $basename .= "/";
            $url      .= "/";
        }

        my $mime_type = $is_dir ? 'directory' : ( Plack::MIME->mime_type($file) || 'text/plain' );
        push @files, [ $url, $basename, $stat[7], $mime_type, HTTP::Date::time2str($stat[9]) ];
    }

	warn "# page_files = ",dump( @page_files );

    my $dir  = Plack::Util::encode_html( $env->{PATH_INFO} );
	my $page = 'empty';

	if ( $req->param('bookreader') ) {

		my $pages; # []
		my $pages_path = "cache/$dir_url/bookreader.json";
		if ( 0 && -e $pages_path ) {
			$pages = decode_json read_file $pages_path;
		} else {
			foreach my $page ( sort { $a <=> $b } @page_files ) {
				my $image = Graphics::Magick->new;
				if ( $page =~ m/\.pdf$/ ) {
					my $cache_dir = "cache/$dir_url/$page/";
					make_path $cache_dir;
					warn "# pdfimages $path/$page -> $cache_dir";
					system 'pdfimages', '-q', '-j', '-p', "$path/$page", $cache_dir;

					# glob split on spaces!
					opendir(my $dh, $cache_dir);
					while (readdir($dh)) {
						warn "## readdir = [$_]\n";
						my $page = "$cache_dir/$_";
						next unless -f $page; # skip . ..

						if ( $page !~ m/\.jpg$/ ) {
							warn "# convert to jpg";
							system 'gm', 'convert', $page, $page . '.jpg';
							unlink $page;
							$page .= '.jpg';
						}

						warn "## ping $page\n";
						die "$page: $!" unless -r $page;
						my ( $w, $h, $size, $format ) = $image->ping($page);
						warn "## image size $w*$h $size $format $page\n";
						push @$pages, [ "/$page", $w, $h ] if $w && $h;
					}
					closedir $dh;

				} else {
					die "$path/$page: $!" unless -r "$path/$page";
					my ( $w, $h, $size, $format ) = $image->ping("$path/$page");
					warn "# image size $w*$h $size $format $path/$page\n";
					push @$pages, [ "$dir_url/$page", $w, $h ] if $w && $h;
				}
			}
			make_basedir $pages_path;
			write_file $pages_path => encode_json( $pages );
			warn "# created $pages_path ", -s $pages_path, " bytes\n";
		}
		warn "# pages = ",dump($pages);
		$page = sprintf $reader_page, $dir, encode_json( $pages ), $dir, '..';

	} else {

		my $files = join "\n", map {
			my $f = $_;
			sprintf $dir_file, map Plack::Util::encode_html($_), @$f;
		} @files;

		$page = sprintf $dir_page, $dir, $dir, $files, 
			@page_files ? '<form><input type=submit name=bookreader value="Read"></form>' . dump( [ @page_files ] ) : '';

	}

    return [ 200, ['Content-Type' => 'text/html; charset=utf-8'], [ $page ] ];
}

1;

__END__

=head1 NAME

Plack::App::BookReader - Internet Archive Book Reader with directory index

=head1 SYNOPSIS

  # app.psgi
  use Plack::App::BookReader;
  my $app = Plack::App::BookReader->new({ root => "/path/to/htdocs" })->to_app;

=head1 DESCRIPTION

This is a static file server PSGI application with directory index a la Apache's mod_autoindex.

=head1 CONFIGURATION

=over 4

=item root

Document root directory. Defaults to the current directory.

=back

=head1 AUTHOR

Dobrica Pavlinusic
Tatsuhiko Miyagawa (based on L<Plack::App::Directory>

=head1 SEE ALSO

L<Plack::App::File>

=cut

