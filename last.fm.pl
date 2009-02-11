#!/usr/bin/perl

use warnings;
use strict;

use DBI;
use Net::LastFM;
use Smart::Comments;

my $user = "gms8994";

my $lastfm = Net::LastFM->new(
        api_key    => 'fa0ece59ef201656ac4731da1960c3f8',
        api_secret => '629b99467bd7d32c1dc3fbccf3a291f7',
        );
my $data = $lastfm->request_signed(
        method => 'user.getWeeklyChartList',
        user   => $user,
        );

my $charts = $data->{'weeklychartlist'}->{'chart'};
my $home_dir = ( getpwuid $< )[ -2 ] . '/';

my $dbh = DBI->connect("dbi:SQLite:dbname=${home_dir}.songbird2/zanii75o.default/db/main\@library.songbirdnest.com.db", "", "", { RaiseError => 1 }, ) or die $DBI::errstr;

my $media_item_sth = $dbh->prepare("SELECT media_item_id FROM resource_properties WHERE property_id = ? AND obj = ? AND media_item_id IN (SELECT media_item_id FROM resource_properties WHERE property_id = ? AND obj = ?)") || die $dbh->errstr;

my $select = $dbh->prepare("SELECT obj FROM resource_properties WHERE media_item_id = ? AND property_id = ?");
my $insert = $dbh->prepare("INSERT INTO resource_properties (media_item_id, property_id, obj) VALUES (?, ?, ?)");
my $update = $dbh->prepare("UPDATE resource_properties SET obj = ? WHERE media_item_id = ? AND property_id = ?");

foreach my $chart (@{$charts}) { ### Weekly Charts [===             ] % done

    my $track_chart_data = $lastfm->request_signed(
        method  => 'user.getWeeklyTrackChart',
        user    => $user,
        from    => $chart->{'from'},
        to      => $chart->{'to'}
    );

    if (ref $track_chart_data->{'weeklytrackchart'}->{'track'} eq 'HASH') {
        use Data::Dumper; die Dumper($track_chart_data->{'weeklytrackchart'}->{'track'});
    }
    foreach my $song (@{$track_chart_data->{'weeklytrackchart'}->{'track'}}) {
        $media_item_sth->execute(1, $song->{'name'}, 3, $song->{'artist'}->{'#text'});
        my ($media_item_id) = $media_item_sth->fetchrow_array();
        next unless $media_item_id;
        $select->execute($media_item_id, 11) || die $dbh->errstr;
        if (my ($existing_value) = $select->fetchrow_array()) {
            if ($existing_value < $chart->{'to'}*1000) {
                $update->execute($chart->{'to'}*1000, $media_item_id, 11) || die $dbh->errstr;
            }
        } else {
            $insert->execute($media_item_id, 11, $chart->{'to'}*1000) || die $dbh->errstr;
        }
    }
    sleep(10);
}
