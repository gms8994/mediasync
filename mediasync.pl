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

# this is the list of paths
$sth = $songbird_dbh->prepare("SELECT media_item_id, obj FROM resource_properties WHERE property_id = 20 AND obj LIKE 'file%';");
$sth->execute() || die $songbird_dbh->errstr;
my $common_string = "";
while (my ($media_item_id, $obj) = $sth->fetchrow_array()) {
    if ($common_string ne "") {
        my @common = &lc_substr($obj, $common_string);
        $common_string = join("", @common);
    } else {
        $common_string = $obj;
    }
}
die $common_string;

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

# http://en.wikipedia.org/wiki/Longest_common_substring_problem
sub lc_substr {
    my ($str1, $str2) = @_; 
    my $l_length = 0; # length of longest common substring
    my $len1 = length $str1; 
    my $len2 = length $str2; 
    my @char1 = (undef, split(//, $str1)); # $str1 as array of chars, indexed from 1
    my @char2 = (undef, split(//, $str2)); # $str2 as array of chars, indexed from 1
    my @lc_suffix; # "longest common suffix" table
    my @substrings; # list of common substrings of length $l_length

    for my $n1 ( 1 .. $len1 ) { 
        for my $n2 ( 1 .. $len2 ) { 
            if ($char1[$n1] eq $char2[$n2]) {
                # We have found a matching character. Is this the first matching character, or a
                # continuation of previous matching characters? If the former, then the length of
                # the previous matching portion is undefined; set to zero.
                $lc_suffix[$n1-1][$n2-1] ||= 0;
                # In either case, declare the match to be one character longer than the match of
                # characters preceding this character.
                $lc_suffix[$n1][$n2] = $lc_suffix[$n1-1][$n2-1] + 1;
                # If the resulting substring is longer than our previously recorded max length ...
                if ($lc_suffix[$n1][$n2] > $l_length) {
                    # ... we record its length as our new max length ...
                    $l_length = $lc_suffix[$n1][$n2];
                    # ... and clear our result list of shorter substrings.
                    @substrings = ();
                }
                # If this substring is equal to our longest ...
                if ($lc_suffix[$n1][$n2] == $l_length) {
                    # ... add it to our list of solutions.
                    push @substrings, substr($str1, ($n1-$l_length), $l_length);
                }
            }
        }
    }   

    return @substrings;
}

