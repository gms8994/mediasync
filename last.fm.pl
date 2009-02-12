#!/usr/bin/perl

use warnings;
use strict;

use DBI;
use File::Find;
use Getopt::Long;
use Net::LastFM;
use Smart::Comments;
use Storable;

my $home_dir = ( getpwuid $< )[ -2 ] . '/';
my $user = "gms8994";
my $cache_dir = ".cache/";
my $limit = 5;
my $history = 1;
my $counts = 1;
my $library = "";

GetOptions ("user=s"      => \$user,
            "cache_dir=s" => \$cache_dir,
            "limit=i"     => \$limit,
            "history!"    => \$history,
            "counts!"     => \$counts,
            "library=s"   => \$library,
            );

my $lastfm = Net::LastFM->new(
        api_key    => 'fa0ece59ef201656ac4731da1960c3f8',
        api_secret => '629b99467bd7d32c1dc3fbccf3a291f7',
        );
if (! -d $cache_dir) { mkdir($cache_dir); }

if (!$library || (! -e $library)) {
    ### No library found.  Looking for it.
    find(\&wanted, $home_dir);
}
### Using library at: $library

my $dbh = DBI->connect("dbi:SQLite:dbname=${library}", "", "", { RaiseError => 1 }, ) or die $DBI::errstr;

my $media_item_sth = $dbh->prepare("SELECT media_item_id FROM resource_properties WHERE property_id = ? AND obj = ? AND media_item_id IN (SELECT media_item_id FROM resource_properties WHERE property_id = ? AND obj = ?)") || die $dbh->errstr;

my $select = $dbh->prepare("SELECT obj FROM resource_properties WHERE media_item_id = ? AND property_id = ?");
my $insert = $dbh->prepare("INSERT INTO resource_properties (media_item_id, property_id, obj) VALUES (?, ?, ?)");
my $update = $dbh->prepare("UPDATE resource_properties SET obj = ? WHERE media_item_id = ? AND property_id = ?");

if ($history) {
    my $data = $lastfm->request_signed(
            method => 'user.getWeeklyChartList',
            user   => $user,
            );
    my $charts = $data->{'weeklychartlist'}->{'chart'};

    foreach my $chart (@{$charts}) { ### Weekly Charts [===             ] % done

        my $cache_file = $cache_dir.$user.$chart->{'from'}.$chart->{'to'};
        my $track_chart_data;
        if (-f $cache_file && (time() - (stat($cache_file))[9] < (86400 * 7))) {
            $track_chart_data = retrieve($cache_file);
        } else {
            $track_chart_data = $lastfm->request_signed(
                method  => 'user.getWeeklyTrackChart',
                user    => $user,
                from    => $chart->{'from'},
                to      => $chart->{'to'}
            );
            store $track_chart_data, $cache_file;
        }

        if (ref $track_chart_data->{'weeklytrackchart'}->{'track'} eq 'ARRAY') {
            foreach my $song (@{$track_chart_data->{'weeklytrackchart'}->{'track'}}) {
                &update_data($chart->{'to'} * 1000, 11, $song->{'name'}, $song->{'artist'}->{'#text'});
            }
        } else {
            my $song = $track_chart_data->{'weeklytrackchart'}->{'track'};
            &update_data($chart->{'to'} * 1000, 11, $song->{'name'}, $song->{'artist'}->{'#text'});
        }
    }
}

if ($counts) {
    my $page = 1; my $total_pages = 0+"Infinity";

    while ($page < $total_pages) { ### Library [===               ] % done

        my $cache_file = $cache_dir.$user."library".$limit.$page;
        my $library_data;
        if (-f $cache_file && (time() - (stat($cache_file))[9] < (86400 * 7))) {
            $library_data = retrieve($cache_file);
        } else {
            $library_data = $lastfm->request_signed(
                    method => 'library.getTracks',
                    user   => $user,
                    limit => $limit,
                    page => $page,
                    );
            store $library_data, $cache_file;
        }

        $total_pages = $library_data->{'tracks'}->{'totalPages'};

        foreach my $track (@{$library_data->{'tracks'}->{'track'}}) {
            my $play_count = $track->{'playcount'};
            &update_data($play_count, 12, $track->{'name'}, $track->{'artist'}->{'name'});
        }
        $page++;
    }
}

sub update_data {
    my ($new_value, $property_id, $song_name, $artist_name) = @_;

    $media_item_sth->execute(1, $song_name, 3, $artist_name) || die $dbh->errstr;
    my ($media_item_id) = $media_item_sth->fetchrow_array();
    return unless $media_item_id;
    $select->execute($media_item_id, $property_id) || die $dbh->errstr;
    if (my ($existing_value) = $select->fetchrow_array()) {
        if (($existing_value =~ /^\d+$/ && $new_value =~ /^\d+$/ && $existing_value < $new_value) || ($existing_value !~ /^$new_value$/)) {
            $update->execute($new_value, $media_item_id, $property_id) || die $dbh->errstr;
        }
    } else {
        $insert->execute($media_item_id, $property_id, $new_value) || die $dbh->errstr;
    }
}
sub wanted {
    if ($_ =~ m/main\@library.songbirdnest.com.db/) {
        $library = $File::Find::name;
        return 1;
    }
    return 0;
}
