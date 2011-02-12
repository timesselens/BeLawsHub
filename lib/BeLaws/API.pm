package BeLaws::API;
use strict;
use warnings;
use Carp qw/croak/;
use BeLaws::Driver::Storage::SQLite;
use BeLaws::Query;
use JSON::XS;
use Plack::Request;
use Data::Dumper;

my $db = new BeLaws::Driver::Storage::SQLite;

our $list = sub {
    my $env = shift;
    my $dbh = $db->get_dbh();

    my $req = new Plack::Request($env);
    my $param = $req->parameters();

    return [ 500, [ 'Content-Type' => 'text/plain' ], [ 'incorrect date YYYY-MM-DD' ] ] unless $param->{date} =~ m/^\d{4}\W?\d{2}\W?\d{2}$/;

    # my @rows = $dbh->selectall_arrayref('select * from belaws_docs where pubdate = ?',{Slice=>{}},$param->{date});
    
    my $fgov = new BeLaws::Query;

    my @rows;
    my $i = 0;
    while(my $obj = $fgov->request($param->{date} . sprintf('%02i',++$i), 'perl')) {
        push @rows, $obj;
        warn Dumper $obj;
        $dbh->do('insert into belaws_docs (docuid,pubid,pubdate,source,body,plain,pages,pdf_href,effective) values (?,?,?,?,?,?,?,?,?)', undef,
                @{$obj}{qw/docuid pubid pubdate source body plain pages pdf_href effective/});
    }

    return [ 200, [ 'Content-Type' => 'application/json' ], [ encode_json(\@rows) ] ];
};

42;
