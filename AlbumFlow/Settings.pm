package Plugins::AlbumFlow::Settings;

# Settings page (Lyrion: Settings > Advanced > AlbumFlow)

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Prefs;
use Slim::Music::VirtualLibraries;

my $prefs = preferences('plugin.albumflow');

sub name { 'PLUGIN_ALBUMFLOW' }

sub page { 'plugins/AlbumFlow/settings/basic.html' }

sub prefs { ($prefs, qw(library theme lang idle colors hacolor)) }

# the virtual libraries (e.g. "without online duplicates") for the library menu
sub beforeRender {
	my ($class, $paramRef) = @_;
	my $libs = Slim::Music::VirtualLibraries->getLibraries() || {};
	$paramRef->{libraries} = [
		sort { lc($a->{name}) cmp lc($b->{name}) }
		map { { id => $_, name => Slim::Music::VirtualLibraries->getNameForId($_) || $libs->{$_}->{name} || $_ } } keys %$libs
	];
}

1;
