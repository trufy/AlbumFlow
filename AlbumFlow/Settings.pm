package Plugins::AlbumFlow::Settings;

# Settings page (Lyrion: Settings > Advanced > AlbumFlow). The TIDAL tweaks
# patch the TIDAL plugin at server start, so changing them needs a restart.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Prefs;

my $prefs = preferences('plugin.albumflow');

sub name { 'PLUGIN_ALBUMFLOW' }

sub page { 'plugins/AlbumFlow/settings/basic.html' }

sub prefs { ($prefs, qw(tidalStreamFix tidalAiFlag)) }

1;
