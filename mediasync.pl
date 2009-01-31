#!/usr/bin/perl

use warnings;
use strict;

use DBI;
use File::Find;
no warnings 'File::Find';

chomp(my $hostname = `hostname`);
my $sync_db_file = ".sqlite_sync_file.db";
my $home_dir = ( getpwuid $< )[ -2 ] . '/';
my $songbird_library;

my $sync_dbh = DBI->connect("dbi:SQLite:dbname=${home_dir}${sync_db_file}", "", "", { RaiseError => 0 }, ) or die $DBI::errstr;

&query($sync_dbh, "CREATE TABLE IF NOT EXISTS hosts (id INTEGER PRIMARY KEY AUTOINCREMENT, name varchar(50) NOT NULL);", "CREATE UNIQUE INDEX IF NOT EXISTS name ON hosts (name)", "INSERT OR IGNORE INTO hosts (name) VALUES (".$sync_dbh->quote($hostname).")", "CREATE TABLE IF NOT EXISTS dirs (id INTEGER PRIMARY KEY AUTOINCREMENT, name varchar(255) NOT NULL)", "CREATE UNIQUE INDEX IF NOT EXISTS name ON dirs (name)", "CREATE TABLE IF NOT EXISTS hosts_to_dirs (host_id INTEGER, dir_id INTEGER);", "CREATE UNIQUE INDEX IF NOT EXISTS host_id_dir_id ON hosts_to_dirs (host_id, dir_id);");

my $sth = $sync_dbh->prepare("SELECT d.name FROM dirs d INNER JOIN hosts_to_dirs htd ON htd.dir_id = d.id INNER JOIN hosts h ON htd.host_id = h.id WHERE h.name = ".$sync_dbh->quote($hostname));
$sth->execute() || die $sync_dbh->errstr;
if (!$sth->rows()) {
    find(\&wanted, $home_dir);
    if ($songbird_library) {
        &query($sync_dbh, "INSERT INTO dirs (name) VALUES  (".$sync_dbh->quote($songbird_library).")");
        my $dir_id = $sync_dbh->last_insert_id(undef, undef, undef, undef);
        &query($sync_dbh, "INSERT INTO hosts_to_dirs (dir_id, host_id) VALUES ($dir_id, (SELECT id FROM hosts WHERE name = ".$sync_dbh->quote($hostname)."))");
    } else {
    }
} else {
    ($songbird_library) = $sth->fetchrow_array();
}
$sth->finish();
$sync_dbh->disconnect();

my $songbird_dbh = DBI->connect("dbi:SQLite:dbname=${songbird_library}", "", "", { RaiseError => 0 }, ) or die $DBI::errstr;




sub query() {
    my ($dbh) = $_[0];

    return 0 unless scalar(@_) > 1;

    for( my $parm = 1; $parm < scalar(@_); $parm++ ) {
        $dbh->do($_[$parm]) || die $_[$parm];
    }
}

sub wanted {
    if ($_ =~ m/main\@library.songbirdnest.com.db/) {
        $songbird_library = $File::Find::name;
        return 1;
    }
    return 0;
}
