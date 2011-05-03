package BeLaws::Frontend;
use strict;
use warnings;
use Carp qw/croak/;
use BeLaws::Driver::Storage::SQLite;
use BeLaws::Query;
use JSON::XS;
use Plack::Request;
use Data::Dumper;
use BeLaws::Format;

my $db = new BeLaws::Driver::Storage::SQLite;

#our $list = sub {
#    my $env = shift;
#    my $dbh = $db->get_dbh();
#
#    my $req = new Plack::Request($env);
#    my $param = $req->parameters();
#
#    warn "q is ".$param->{'q'};
#
#    my $rows = $dbh->selectall_arrayref('select * from belaws_docs where plain match ? order by docid desc limit 20',{Slice=>{}},$param->{'q'});
#
#    foreach (@$rows) {
#        $_->{pretty} = BeLaws::Format::prettify($_->{body})
#    }
#    
#    return [ 200, [ 'Content-Type' => 'application/json' ], [ encode_json($rows) ] ];
#};

our $doc = sub {
    my $env = shift;
    my $dbh = $db->get_dbh();

    my $req = new Plack::Request($env);
    my $param = $req->parameters();

    warn "docuid is ".$param->{'id'};
    
    my $rows = $dbh->selectall_arrayref('select * from belaws_docs where docuid = ? limit 1',{Slice=>{}},$param->{'id'});

    return [ 404, [ 'Content-Type' => 'text/plain' ], [ 'not found' ] ] unless scalar @$rows > 0;

    return [ 200, [ 'Content-Type' => 'text/html; charset=utf-8' ], [ BeLaws::Format::prettify($rows->[0]->{body}) ] ];

};

42;

__DATA__
<html>
    <head>
        <script src="/js/main.js" type="text/javascript" charset="utf-8"></script>
        <link rel="stylesheet" href="/css/design.css" type="text/css" media="screen" charset="utf-8"/>
    </head>
    <body>
        <!--{INCLUDE_TEMPLATE}-->
    </body>
</html>

