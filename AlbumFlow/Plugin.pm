package Plugins::AlbumFlow::Plugin;

# AlbumFlow: a slim touch skin with a 3D album flow.
# The skin itself lives in HTML/AlbumFlow and is served by LMS at
# http://<server>:9000/AlbumFlow/ - this module loads the plugin and adds
# two small JSON-RPC commands for the TIDAL favourite tracks ("Meine Lieder"):
#
#   <player> albumflow tidalfavs [refresh:1]
#       favourite tracks of the player's TIDAL account, newest first
#       (the TIDAL plugin itself only lists them alphabetically)
#   <player> albumflow tidalplay cmd:load|insert|add ids:<id,id,...> [index:<n>]
#       put those TIDAL tracks on the playlist, optionally starting at index n
#   <player> albumflow tidalfav id:<id> [set:0|1]
#       heart: favourite state of a TIDAL track, optionally add/remove it (also answers ai:0|1)
#   <player> albumflow tidalai ids:<id,...>
#       which of these TIDAL tracks are flagged as AI generated

use strict;
use base qw(Slim::Plugin::Base);

use Slim::Utils::Log;
use Slim::Utils::Cache;
use Slim::Utils::Prefs;

my $prefs = preferences('plugin.albumflow');
$prefs->init({ library => '' });

my $log = Slim::Utils::Log->addLogCategory({
	category     => 'plugin.albumflow',
	defaultLevel => 'ERROR',
	description  => 'PLUGIN_ALBUMFLOW',
});

use constant FAVS_TTL => 600;
my %favsCache;   # TIDAL userId -> { ts => time, tracks => [...] }

sub initPlugin {
	my $class = shift;
	$class->SUPER::initPlugin(@_);

	if (main::WEBUI) {
		require Plugins::AlbumFlow::Settings;
		Plugins::AlbumFlow::Settings->new;
	}

	Slim::Control::Request::addDispatch(['albumflow', 'tidalfavs'], [1, 1, 1, \&_tidalFavs]);
	Slim::Control::Request::addDispatch(['albumflow', 'tidalplay'], [1, 0, 1, \&_tidalPlay]);
	Slim::Control::Request::addDispatch(['albumflow', 'tidalplaylists'], [1, 1, 1, \&_tidalPlaylists]);
	Slim::Control::Request::addDispatch(['albumflow', 'tidalsearch'], [1, 1, 1, \&_tidalSearch]);
	Slim::Control::Request::addDispatch(['albumflow', 'tidalalbum'], [1, 1, 1, \&_tidalAlbum]);
	Slim::Control::Request::addDispatch(['albumflow', 'tidalplaylist'], [1, 1, 1, \&_tidalPlaylistTracks]);
	Slim::Control::Request::addDispatch(['albumflow', 'tidalmixes'], [1, 1, 1, \&_tidalMixes]);
	Slim::Control::Request::addDispatch(['albumflow', 'tidalmix'], [1, 1, 1, \&_tidalMixTracks]);
	Slim::Control::Request::addDispatch(['albumflow', 'tidalhome'], [1, 1, 1, \&_tidalHome]);
	Slim::Control::Request::addDispatch(['albumflow', 'tidalradio'], [1, 0, 1, \&_tidalRadio]);
	Slim::Control::Request::addDispatch(['albumflow', 'tidalfav'], [1, 0, 1, \&_tidalFav]);
	Slim::Control::Request::addDispatch(['albumflow', 'tidalai'], [1, 1, 1, \&_tidalAi]);
}

# <player> albumflow tidalai ids:<id,id,...>
#   which of these TIDAL tracks TIDAL flags as AI generated ("ai": true in the
#   track data). Answers ai:<comma separated ids> (empty if none).
sub _tidalAi {
	my $request = shift;
	my $api = _tidalApi($request->client);
	my @ids = grep { /^\d+$/ } split /,/, ($request->getParam('ids') || '');
	if (!$api || !@ids) {
		$request->setStatusBadParams;
		return;
	}
	$request->setStatusProcessing;
	_aiFlags($api, \@ids, sub {
		my $flags = shift;
		$request->addResult(ai => join(',', grep { $flags->{$_} } @ids));
		$request->setStatusDone;
	});
}

# AI flag per track id: from the TIDAL plugin's metadata cache (which postinitPlugin
# makes keep "ai"), tracks not cached yet (or cached before that) are fetched once
use constant AI_FETCH_MAX => 60;
sub _aiFlags {
	my ($api, $ids, $cb) = @_;
	my $cache = Slim::Utils::Cache->new;
	my (%flags, @missing);
	foreach my $id (@$ids) {
		my $meta = $cache->get('tidal_meta_' . $id);
		if (ref $meta && exists $meta->{ai}) { $flags{$id} = $meta->{ai} ? 1 : 0 }
		else { push @missing, $id }
	}
	splice @missing, AI_FETCH_MAX if @missing > AI_FETCH_MAX;
	return $cb->(\%flags) unless @missing;

	my $pending = scalar @missing;
	foreach my $id (@missing) {
		$api->track(sub {
			my $meta = shift;
			$flags{$id} = $meta && $meta->{ai} ? 1 : 0;
			$cb->(\%flags) unless --$pending;
		}, $id);
	}
}

# <player> albumflow tidalfav id:<track id> [set:0|1]
#   heart button: is this TIDAL track a favourite of the player's account?
#   With set: add (1) or remove (0) it first. Answers fav:0|1.
sub _tidalFav {
	my $request = shift;
	my $client  = $request->client;

	my $id     = $request->getParam('id');
	my $set    = $request->getParam('set');
	my $api    = _tidalApi($client);
	my $userId = $api && $api->userId;
	if (!$userId || !defined $id || $id !~ /^\d+$/ || (defined $set && $set !~ /^[01]$/)) {
		$request->setStatusBadParams;
		return;
	}

	$request->setStatusProcessing;

	_loadFavs($api, $userId, 0, sub {
		my $tracks = shift;
		if (!$tracks) {
			$request->addResult(error => 'TIDAL request failed');
			$request->setStatusDone;
			return;
		}

		my $isFav = (grep { $_->{id} eq $id } @$tracks) ? 1 : 0;
		if (!defined $set || $set == $isFav) {
			$request->addResult(fav => $isFav);
			_aiFlags($api, [$id], sub {
				$request->addResult(ai => $_[0]->{$id} ? 1 : 0);
				$request->setStatusDone;
			});
			return;
		}

		$api->updateFavorite(sub {
			my $cached = $favsCache{$userId};
			if ($set) {
				# put it on top of "Meine Lieder" right away (newest first)
				$api->track(sub {
					my $meta = shift || {};
					my @t = gmtime();
					unshift @{$cached->{tracks}}, {
						id       => $id,
						title    => $meta->{title},
						artist   => ref $meta->{artist} ? $meta->{artist}->{name} : $meta->{artist},
						album    => $meta->{album},
						duration => $meta->{duration},
						cover    => $meta->{cover},
						ai       => $meta->{ai} ? 1 : undef,
						added    => sprintf('%04d-%02d-%02dT%02d:%02d:%02d.000+0000', $t[5] + 1900, $t[4] + 1, @t[3, 2, 1, 0]),
					} if $cached;
					$request->addResult(fav => 1);
					$request->setStatusDone;
				}, $id);
			}
			else {
				$cached->{tracks} = [ grep { $_->{id} ne $id } @{$cached->{tracks}} ] if $cached;
				$request->addResult(fav => 0);
				$request->setStatusDone;
			}
		}, $set ? 'add' : 'remove', 'track', $id);
	});
}

# <player> albumflow tidalradio id:<track id> [list:1]
#   "Titelradio": replace the playlist with TIDAL's track radio for that track and play it
sub _tidalRadio {
	my $request = shift;
	my $client  = $request->client;

	my $id  = $request->getParam('id');
	my $api = _tidalApi($client);
	if (!$api || !defined $id || $id !~ /^\d+$/) {
		$request->setStatusBadParams;
		return;
	}

	$request->setStatusProcessing;

	my $listOnly = $request->getParam('list');

	$api->trackRadio(sub {
		my $tracks = shift || [];
		# list:1 only returns the radio tracks (the skin shows them before playing)
		return _addTrackRows($request, $tracks) if $listOnly;

		my $ext = Plugins::TIDAL::API::getFormat();
		my @objs = grep { $_ } map {
			Slim::Schema->objectForUrl({ url => "tidal://$_->{id}.$ext", create => 1 })
		} grep { $_ && $_->{id} } @$tracks;

		if (@objs) {
			$client->execute(['playlist', 'loadtracks', 'listRef', \@objs]);
		}
		$request->addResult(count => scalar @objs);
		$request->setStatusDone;
	}, $id);
}

sub _noAccount {
	my $request = shift;
	$request->addResult(error => 'No TIDAL account');
	$request->addResult(count => 0);
	$request->setStatusDone;
}

sub _addTrackRows {
	my ($request, $tracks) = @_;
	my $i = 0;
	foreach my $t (@{ $tracks || [] }) {
		next unless $t && $t->{id};
		$request->addResultLoop('tracks_loop', $i, 'id', $t->{id});
		$request->addResultLoop('tracks_loop', $i, 'title', $t->{title} // '');
		$request->addResultLoop('tracks_loop', $i, 'ai', 1) if $t->{ai};
		my $artist = ref $t->{artist} ? $t->{artist}->{name} : $t->{artist};
		$request->addResultLoop('tracks_loop', $i, 'artist', $artist) if $artist;
		$request->addResultLoop('tracks_loop', $i, 'duration', $t->{duration}) if $t->{duration};
		$request->addResultLoop('tracks_loop', $i, 'cover', $t->{cover}) if $t->{cover} && $t->{cover} =~ /^https?:/;
		$i++;
	}
	$request->addResult(count => $i);
	$request->setStatusDone;
}

# <player> albumflow tidalmixes
#   "My mixes" (daily/track mixes) of the player's TIDAL account
sub _tidalMixes {
	my $request = shift;
	my $api = _tidalApi($request->client);
	return _noAccount($request) unless $api && $api->userId;

	$request->setStatusProcessing;
	$api->myMixes(sub {
		my $items = shift || [];
		my $i = 0;
		foreach my $m (@$items) {
			next unless ref $m && $m->{id};
			my %seen;
			my $sub = join(', ', grep { !$seen{$_}++ } map { $_->{name} } grep { ref $_ } @{ $m->{artists} || [] });
			my $cover = Plugins::TIDAL::API->getImageUrl({ %$m });
			$request->addResultLoop('items_loop', $i, 'kind', 'mix');
			$request->addResultLoop('items_loop', $i, 'id', $m->{id});
			$request->addResultLoop('items_loop', $i, 'title', $m->{title} // '');
			$request->addResultLoop('items_loop', $i, 'sub', $sub || $m->{subTitle} || '');
			$request->addResultLoop('items_loop', $i, 'cover', $cover) if $cover;
			$i++;
		}
		$request->addResult(count => $i);
		$request->setStatusDone;
	});
}

# <player> albumflow tidalmix id:<mix id>
sub _tidalMixTracks {
	my $request = shift;
	my $id  = $request->getParam('id');
	my $api = _tidalApi($request->client);
	if (!$api || !defined $id || $id !~ /^[0-9a-z]+$/i) {
		$request->setStatusBadParams;
		return;
	}
	$request->setStatusProcessing;
	$api->mix(sub { _addTrackRows($request, shift) }, $id);
}

# <player> albumflow tidalhome
#   "Vorschläge": albums, playlists and mixes from the account's personal TIDAL
#   home page, each tagged with the title of its module ("Für dich", ...)
sub _tidalHome {
	my $request = shift;
	my $api = _tidalApi($request->client);
	return _noAccount($request) unless $api && $api->userId;

	$request->setStatusProcessing;

	# only new things: skip the home modules that show the user's own stuff, and any
	# playlist that is already in the account's collection ("My playlists")
	my $ownModules = qr/verkn.{1,2}pf|shortcut|k.{1,2}rzlich|recently|zuletzt|deine top|your top|vergessen|forgotten|gerade aktualisiert|recently updated|meine|my collection|deine sammlung/i;

	$api->getCollectionPlaylists(sub {
	my %seen = map { ("playlist:$_->{uuid}" => 1) } grep { ref $_ && $_->{uuid} } @{ shift || [] };
	$api->home(sub {
		my $modules = shift || [];
		my $i = 0;
		foreach my $module (@$modules) {
			next unless ref $module;
			next if ($module->{title} || '') =~ $ownModules;
			my $entries = ($module->{pagedList} && $module->{pagedList}->{items}) || $module->{items} || [];
			foreach my $e (@$entries) {
				next unless ref $e;
				my $type = uc($e->{type} || '');
				my $it = ($e->{item} && ref $e->{item}) ? $e->{item} : $e;
				$type = uc($it->{type} || '') if $type !~ /^(?:ALBUM|PLAYLIST|MIX)$/ && $type !~ /TRACK|ARTIST|VIDEO/;
				my $kind = $it->{uuid} ? 'playlist'
					: ($type eq 'MIX' || $it->{mixType}) ? 'mix'
					: ($type eq 'ALBUM' || $type =~ /^(?:EP|SINGLE)$/ || ($it->{releaseDate} && defined $it->{numberOfTracks})) ? 'album'
					: undef;
				next unless $kind;
				my $id = $kind eq 'playlist' ? $it->{uuid} : $it->{id};
				next unless $id && !$seen{"$kind:$id"}++;
				my $sub = $kind eq 'album' ? _artistName($it)
					: $kind eq 'mix' ? ($it->{subTitle} || '')
					: ($it->{numberOfTracks} ? "$it->{numberOfTracks} Titel" : '');
				my $cover = Plugins::TIDAL::API->getImageUrl({ %$it }, 0, $kind eq 'mix' ? undef : $kind);
				$request->addResultLoop('items_loop', $i, 'kind', $kind);
				$request->addResultLoop('items_loop', $i, 'id', $id);
				$request->addResultLoop('items_loop', $i, 'title', $it->{title} // '');
				$request->addResultLoop('items_loop', $i, 'sub', $sub) if $sub;
				$request->addResultLoop('items_loop', $i, 'module', $module->{title} || '');
				$request->addResultLoop('items_loop', $i, 'cover', $cover) if $cover && $cover =~ /^https?:/;
				$i++;
				last if $i >= 200;
			}
			last if $i >= 200;
		}
		$request->addResult(count => $i);
		$request->setStatusDone;
	});
	});
}

# <player> albumflow tidalplaylist uuid:<playlist uuid>
#   tracks of a TIDAL playlist (also fills the TIDAL plugin's metadata cache)
sub _tidalPlaylistTracks {
	my $request = shift;
	my $client  = $request->client;

	my $uuid = $request->getParam('uuid');
	my $api  = _tidalApi($client);
	if (!$api || !defined $uuid || $uuid !~ /^[0-9a-f-]{20,}$/i) {
		$request->setStatusBadParams;
		return;
	}

	$request->setStatusProcessing;

	$api->playlist(sub {
		my $tracks = shift || [];
		my $i = 0;
		foreach my $t (@$tracks) {
			next unless $t && $t->{id};
			$request->addResultLoop('tracks_loop', $i, 'id', $t->{id});
			$request->addResultLoop('tracks_loop', $i, 'title', $t->{title} // '');
			$request->addResultLoop('tracks_loop', $i, 'ai', 1) if $t->{ai};
			my $artist = ref $t->{artist} ? $t->{artist}->{name} : $t->{artist};
			$request->addResultLoop('tracks_loop', $i, 'artist', $artist) if $artist;
			$request->addResultLoop('tracks_loop', $i, 'cover', $t->{cover}) if $t->{cover} && $t->{cover} =~ /^https?:/;
			$request->addResultLoop('tracks_loop', $i, 'duration', $t->{duration}) if $t->{duration};
			$i++;
		}
		$request->addResult(count => $i);
		$request->setStatusDone;
	}, $uuid);
}

sub _artistName {
	my $item = shift;
	return $item->{artist}->{name} if ref $item->{artist};
	my ($main) = grep { ($_->{type} || '') eq 'MAIN' || $_->{main} } @{ $item->{artists} || [] };
	$main ||= ($item->{artists} || [])->[0];
	return $main ? $main->{name} : '';
}

# <player> albumflow tidalsearch term:<text> [limit:<n>]
#   full TIDAL catalogue search (albums), with the player's TIDAL account
sub _tidalSearch {
	my $request = shift;
	my $client  = $request->client;

	my $term = $request->getParam('term');
	my $api  = _tidalApi($client);
	if (!$api || !$api->userId || !defined $term || length($term) < 2) {
		$request->addResult(count => 0);
		$request->addResult(error => 'No TIDAL account') if !$api || !$api->userId;
		$request->setStatusDone;
		return;
	}

	my $limit = $request->getParam('limit');
	$limit = 40 unless $limit && $limit =~ /^\d+$/ && $limit <= 100;

	$request->setStatusProcessing;

	$api->search(sub {
		my $items = shift || [];
		my $i = 0;
		foreach my $a (@$items) {
			next unless ref $a && $a->{id};
			my $cover = Plugins::TIDAL::API->getImageUrl($a, 0, 'album');
			my ($year) = ($a->{releaseDate} || '') =~ /^(\d{4})/;
			$request->addResultLoop('albums_loop', $i, 'id', $a->{id});
			$request->addResultLoop('albums_loop', $i, 'title', $a->{title} // '');
			$request->addResultLoop('albums_loop', $i, 'artist', _artistName($a));
			$request->addResultLoop('albums_loop', $i, 'year', $year) if $year;
			$request->addResultLoop('albums_loop', $i, 'cover', $cover) if $cover;
			$request->addResultLoop('albums_loop', $i, 'tracks', $a->{numberOfTracks} // 0);
			$i++;
		}
		$request->addResult(count => $i);
		$request->setStatusDone;
	}, { type => 'albums', search => $term, limit => $limit });
}

# <player> albumflow tidalalbum id:<album id>
#   tracks of a TIDAL album (also fills the TIDAL plugin's metadata cache)
sub _tidalAlbum {
	my $request = shift;
	my $client  = $request->client;

	my $id  = $request->getParam('id');
	my $api = _tidalApi($client);
	if (!$api || !defined $id || $id !~ /^\d+$/) {
		$request->setStatusBadParams;
		return;
	}

	$request->setStatusProcessing;

	$api->albumTracks(sub {
		my $tracks = shift || [];
		my $i = 0;
		foreach my $t (@$tracks) {
			next unless $t && $t->{id};
			$request->addResultLoop('tracks_loop', $i, 'id', $t->{id});
			$request->addResultLoop('tracks_loop', $i, 'title', $t->{title} // '');
			$request->addResultLoop('tracks_loop', $i, 'ai', 1) if $t->{ai};
			$request->addResultLoop('tracks_loop', $i, 'duration', $t->{duration}) if $t->{duration};
			$request->addResultLoop('tracks_loop', $i, 'tracknum', $t->{tracknum}) if $t->{tracknum};
			$request->addResultLoop('tracks_loop', $i, 'disc', $t->{disc}) if $t->{disc};
			$i++;
		}
		$request->addResult(count => $i);
		$request->setStatusDone;
	}, $id);
}

# <player> albumflow tidalplaylists [refresh:1]
#   "My playlists" of the player's TIDAL account (own + favourited), via the
#   TIDAL plugin's own cached collection lookup. mine:1 = created by this account.
sub _tidalPlaylists {
	my $request = shift;
	my $client  = $request->client;

	my $api    = _tidalApi($client);
	my $userId = $api && $api->userId;
	if (!$userId) {
		$request->addResult(error => 'No TIDAL account');
		$request->setStatusDone;
		return;
	}

	$request->setStatusProcessing;

	$api->getCollectionPlaylists(sub {
		my $items = shift || [];
		my $i = 0;
		foreach my $p (@$items) {
			next unless $p && $p->{uuid};
			my $creator = ref $p->{creator} ? $p->{creator}->{id} : undef;
			$request->addResultLoop('playlists_loop', $i, 'uuid', $p->{uuid});
			$request->addResultLoop('playlists_loop', $i, 'title', $p->{title} // '');
			$request->addResultLoop('playlists_loop', $i, 'tracks', $p->{numberOfTracks} // 0);
			$request->addResultLoop('playlists_loop', $i, 'mine', (defined $creator && $creator eq $userId) ? 1 : 0);
			my $cover = Plugins::TIDAL::API->getImageUrl({ %$p }, 0, 'playlist');
			$request->addResultLoop('playlists_loop', $i, 'cover', $cover) if $cover;
			$request->addResultLoop('playlists_loop', $i, 'updated', $p->{lastUpdated}) if $p->{lastUpdated};
			$i++;
		}
		$request->addResult(count => $i);
		$request->setStatusDone;
	}, $request->getParam('refresh') ? 1 : 0);
}

sub _tidalApi {
	my $client = shift;
	return unless Slim::Utils::PluginManager->isEnabled('Plugins::TIDAL::Plugin');
	return eval { Plugins::TIDAL::Plugin::getAPIHandler($client) };
}

sub _tidalFavs {
	my $request = shift;
	my $client  = $request->client;

	my $api    = _tidalApi($client);
	my $userId = $api && $api->userId;
	if (!$userId) {
		$request->addResult(error => 'No TIDAL account');
		$request->setStatusDone;
		return;
	}

	$request->setStatusProcessing;

	_loadFavs($api, $userId, $request->getParam('refresh') ? 1 : 0, sub {
		my $tracks = shift;
		if (!$tracks) {
			$request->addResult(error => 'TIDAL request failed');
			$request->setStatusDone;
			return;
		}
		_addTracks($request, $tracks);
	});
}

# favourite tracks of a TIDAL account, newest first, cached for FAVS_TTL
sub _loadFavs {
	my ($api, $userId, $force, $cb) = @_;

	my $cached = $favsCache{$userId};
	if ($cached && !$force && time() - $cached->{ts} < FAVS_TTL) {
		$cb->($cached->{tracks});
		return;
	}

	$api->_get("/users/$userId/favorites/tracks", sub {
		my $result = shift;

		if (!$result || $result->{error} || !$result->{items}) {
			$log->error('Could not get TIDAL favourite tracks: ' . ($result && $result->{error} || 'no result'));
			$cb->();
			return;
		}

		my @tracks;
		foreach my $entry (@{$result->{items}}) {
			# also fills the TIDAL plugin's metadata cache used while playing
			my ($meta) = @{ Plugins::TIDAL::API->cacheTrackMetadata([ $entry->{item} ]) };
			next unless $meta && $meta->{id};
			push @tracks, {
				id       => $meta->{id},
				title    => $meta->{title},
				artist   => ref $meta->{artist} ? $meta->{artist}->{name} : $meta->{artist},
				album    => $meta->{album},
				duration => $meta->{duration},
				cover    => $meta->{cover},
				added    => $entry->{created},
				ai       => $meta->{ai} ? 1 : undef,
			};
		}

		# newest first even if TIDAL ignores the order parameters (ISO timestamps sort as strings)
		@tracks = sort { ($b->{added} || '') cmp ($a->{added} || '') } @tracks;

		$favsCache{$userId} = { ts => time(), tracks => \@tracks };
		$cb->(\@tracks);
	}, {
		_nocache       => 1,
		limit          => 5000,
		order          => 'DATE',
		orderDirection => 'DESC',
	});
}

sub _addTracks {
	my ($request, $tracks) = @_;

	$request->addResult(count => scalar @$tracks);
	my $i = 0;
	foreach my $track (@$tracks) {
		while (my ($k, $v) = each %$track) {
			$request->addResultLoop('tracks_loop', $i, $k, $v) if defined $v;
		}
		$i++;
	}
	$request->setStatusDone;
}

sub _tidalPlay {
	my $request = shift;
	my $client  = $request->client;

	my $cmd = $request->getParam('cmd') || 'load';
	my @ids = grep { /^\d+$/ } split /,/, ($request->getParam('ids') || '');

	if (!@ids || $cmd !~ /^(?:load|insert|add)$/ || !_tidalApi($client)) {
		$request->setStatusBadParams;
		return;
	}

	my $ext    = Plugins::TIDAL::API::getFormat();
	my @tracks = grep { $_ } map {
		Slim::Schema->objectForUrl({ url => "tidal://$_.$ext", create => 1 })
	} @ids;

	my $index = $request->getParam('index');
	$index = undef unless defined $index && $index =~ /^\d+$/ && $index < @tracks;

	$client->execute(['playlist', $cmd . 'tracks', 'listRef', \@tracks, undef, $cmd eq 'load' ? $index : undef]);
	$request->setStatusDone;
}

1;
