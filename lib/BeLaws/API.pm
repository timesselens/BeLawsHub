package BeLaws::API;
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

our $list = sub {
    my $env = shift;
    my $dbh = $db->get_dbh();

    my $req = new Plack::Request($env);
    my $param = $req->parameters();

    warn "q is ".$param->{'q'};

    my $rows = $dbh->selectall_arrayref('select * from belaws_docs where plain match ? order by docid desc limit 200',{Slice=>{}},$param->{'q'});

    return [ 200, [ 'Content-Type' => 'application/json' ], [ encode_json($rows) ] ];
};

our $doc = sub {
    my $env = shift;
    my $dbh = $db->get_dbh();

    my $req = new Plack::Request($env);
    my $param = $req->parameters();

    warn "docuid is ".$param->{'docuid'};

    my $rows = $dbh->selectall_arrayref('select * from belaws_docs where docuid = ? limit 1',{Slice=>{}},$param->{'docuid'});
};


### private functions ###############################################################################################################################
sub import_law_from_dir {
    my $dir = shift;

    for my $file (<$dir/*.html>) {
        import_law_from_file($file);
    }
}

sub import_law_from_file { 
    my $file = shift;
    my $dbh = $db->get_dbh();
    my $fgov = new BeLaws::Query;
    my $obj = $fgov->parse_response($file, 'perl');
    for(qw/title docuid pubid pubdate body plain effective/) {
        unless ($obj->{$_}) { print "[$file] has no $_\n"; }
    }
    # print "[".$obj->{docuid}."] inserting record into db with title ".$obj->{title}."\n";
    $dbh->do('insert into belaws_docs (title,docuid,pubid,pubdate,source,body,plain,pages,pdf_href,effective) values (?,?,?,?,?,?,?,?,?,?)', undef,
            @{$obj}{qw/title docuid pubid pubdate source body plain pages pdf_href effective/});
}

42;
