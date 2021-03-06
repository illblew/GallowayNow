#!/usr/bin/env perl

use strict;
use warnings;
use 5.010;

use FindBin;
BEGIN { unshift @INC, "$FindBin::Bin/../lib" }

use DBI;
use XML::RSS;
use GallowayNow;
use Mojo::UserAgent;
use POSIX 'strftime';

my $url = 'http://www2.pressofac.com/classifieds/public_notices/legals/?query=galloway&limit=200';
my $dbh = DBI->connect( 'dbi:SQLite:dbname=' . $GallowayNow::notices_db );

#
# Retrieve Currently Listed Notices
#

my $res = Mojo::UserAgent->new->get($url)->res;
my $seen = $dbh->prepare(
    q{
    SELECT `id` FROM `Notice` WHERE `online_id` = ?
} );

my $insert = $dbh->prepare(
    q{
    INSERT INTO `Notice` (online_id, pub_id, seen_date, title, body)
    VALUES (?, ?, DATE('now'), ?, ? )
    }
);

for my $notice ( reverse $res->dom->find('.admarket-ad-listing')->each ) {

    # parse stuffs
    my $title    = $notice->at('h3 > a')->text;
    my $link     = $notice->at('h3 > a')->attrs('href');
    my $text     = $notice->at('.toggleAd')->text(0);
    my ($id)     = ( $link =~ m|/classifieds/ads/(\d+)/$| );
    my ($pub_id) = ($text) =~ m| #(\d+) Pub Date|;

    # have we seen this?
    $seen->execute($id);
    my ($rowid) = $seen->fetchrow_array();
    if ($rowid) {
        say "We've seen $title - $id  - $pub_id - $link";
        next;
    }

    # it's new
    $insert->execute( $id, $pub_id, $title, $text );
    say "$title - $id  - $pub_id - $link";
    say $text;
    say '*' x 50;
}

#
# Generate RSS Feed
#

my $q   = $dbh->prepare(
    q{
    SELECT *, strftime("%s" ,seen_date) + (3600 * 11) as seen_ts FROM `Notice`
    ORDER BY `id` DESC LIMIT 25
} );
$q->execute;

my $rss = XML::RSS->new( version => '2.0' );

$rss->channel(
    title       => "Galloway Public Notices",
    link        => "http://gallowaynow.com/notices/",
    language    => 'en',
    description => "Press of Atlantic City Public Notices Matching Galloway",
    rating => '(PICS-1.1 "http://www.classify.org/safesurf/" 1 r (SS~~000 1))',

);

while ( my $row = $q->fetchrow_hashref ) {

    $rss->add_item(
        title => $row->{title},
        permaLink =>
            "http://gallowaynow.com/notice/$row->{id}",
        description => $row->{body},
        pubDate     => strftime( "%a, %d %b %Y %T %z", localtime $row->{seen_ts} ) );
}

$rss->save( $FindBin::Bin . '/../public/public_notices.xml' );

__END__

CREATE TABLE `Notice` (
    `id` Integer Primary Key NOT NULL,
    `online_id` Integer NOT NULL,
    `pub_id` Integer NOT NULL,
    `pub_date` DATE,
    `seen_date` DATE NOT NULL,
    `title` Text NOT NULL,
    `body` Text NOT NULL
);

CREATE UNIQUE INDEX online_id_idx ON Notice (online_id);


