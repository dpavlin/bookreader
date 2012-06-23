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
use File::Path qw(make_path);
use Graphics::Magick;

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

    if (-f $path) {

		my $req = Plack::Request->new($env);
		if ( my $reduce = $req->param('reduce') ) {
			$reduce = int($reduce); # BookReader javascript somethimes returns float
			warn "# -scale 1/$reduce $path\n";

			my $cache_path = "cache/$path.reduce.$reduce.jpg";
			if ( $reduce <= 1 ) {
				$cache_path = $path;
			} elsif ( ! -e $cache_path ) {
				my $image = Graphics::Magick->new( magick => 'jpg' );
				$image->Read($path);
				my ( $w, $h ) = $image->Get('width','height');
				$image->Resize(
					width  => $w / $reduce,
					height => $h / $reduce
				);
				$image->Write( filename => $cache_path );
				warn "# created $cache_path ", -s $cache_path, " bytes\n";
			}

        	return $self->SUPER::serve_path($env, $cache_path, $fullpath);

		}

        return $self->SUPER::serve_path($env, $path, $fullpath);
    }

    my $dir_url = $env->{SCRIPT_NAME} . $env->{PATH_INFO};

    if ($dir_url !~ m{/$}) {
        return $self->return_dir_redirect($env);
    }

    my @files = ([ "../", "Parent Directory", '', '', '' ]);

    my $dh = DirHandle->new($path);
    my @children;
    while (defined(my $ent = $dh->read)) {
        next if $ent eq '.';
        push @children, $ent;
    }

	my @page_files;

    for my $basename (sort { $a cmp $b } @children) {
		push @page_files, $basename if $basename =~ m/\.jpg$/;
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

    my $dir  = Plack::Util::encode_html( $env->{PATH_INFO} );
    my $files = join "\n", map {
        my $f = $_;
        sprintf $dir_file, map Plack::Util::encode_html($_), @$f;
    } @files;

	my $meta = {
		page_urls => [ map { "$dir_url/$_" } sort { $a <=> $b } @page_files ],
	};
    my $page  = sprintf $dir_page, $dir, $dir, $files, dump( $meta );

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

