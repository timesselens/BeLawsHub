package BeLaws::API;
use strict;
use warnings;
use Carp qw/croak/;
use BeLaws::Driver::Storage::PostgreSQL qw/$db/;
use BeLaws::Query::ejustice_fgov::document;
use BeLaws::Query::raadvanstate;
use BeLaws::Query::juridat;
use BeLaws::Format::ejustice_fgov;
use BeLaws::Spider::codex_vlaanderen;
use BeLaws::Driver::LWP;
use JSON::XS;
use Plack::Request;
use Data::Dumper;
use BeLaws::Format::ejustice_fgov;
use Text::Diff;
use Encode qw/decode encode/; 
use Capture::Tiny qw/capture/;
use Test::Builder;
use HTTP::Exception; sub throw { HTTP::Exception->throw(shift,status_message => shift) };
use Data::Dumper;
use encoding "utf-8"; # affects \w

sub search {
    my $env = shift;
    my $as_object = shift;

    my $dbh = $db->get_dbh();

    my $req = new Plack::Request($env);
    my $param = $req->parameters();

    # untaint incoming variables
    my ($query) = ($param->{'q'} =~ m/^([\w\d\ :\-\/]+)$/)
                    or return [ 500, [ 'Content-Type' => 'text/plain' ], [ 'illegal query string' ] ];
    my ($lang) = ($param->{'lang'} || 'nl' =~ m/(nl|fr)/);

    # trim so the split is more certain
    $query =~ s/^\s+|\s+$//g;
    $query =~ s/\s+/\ /g;

    # split the query into parts by space (tokenizing)
    my @parts = split ' ',$query;

    # rebuild the query containing only words withing colons
    my $q = join ' ', grep { !/:/ } @parts;

    # filter parts having a colon in them, put them into hash
    my %filters = map { split ':', $_, 2 } grep { /:/ } @parts;

    # warn "q is ".$param->{'q'}." filters are ".Dumper(\%filters);

    my $sql = qq/
    select docuid, docdate, ts_headline('public.belaws_$lang',title, tsq, 'HighlightAll=TRUE') as title,
        (select cat from __staatsblad_${lang}_docuid_per_cat where docuid = any(docuids)) as cat,
        ts_rank_cd(fts, tsq) as rank,
        '$lang' as lang
        from (select docuid,docdate,title,tsq,fts
                from staatsblad_$lang, plainto_tsquery('public.belaws_$lang',?) as tsq
                where fts @@ tsq)
        as result order by rank desc/;

    my $rows = $dbh->selectall_arrayref($sql, {Slice=>{}},$q);

    return $as_object ? $rows : [ 200, [ 'Content-Type' => 'application/json; charset=utf-8' ], [ encode_json($rows) ]] ;
};

sub class_person {
    my $env = shift;
    my $dbh = $db->get_dbh();

    my $req = new Plack::Request($env);
    my $param = $req->parameters();
    my ($lang) = ($param->{'lang'} || 'nl' =~ m/(nl|fr)/);

    my $sql = qq/
    select name,
            count(*) as count,
            array_agg(docuid) as docuids
     from (select name, unnest(staatsblad_${lang}_docuids) as docuid from person) as foo
     where docuid in (select docuid from staatsblad_$lang where plainto_tsquery('public.belaws_$lang',?) @@ fts)
     group by name order by count desc/;

    my $rows = $dbh->selectall_arrayref($sql, {Slice=>{}},$param->{'q'});

    return [ 200, [ 'Content-Type' => 'application/json; charset=utf-8' ], [ encode_json($rows) ] ];
};

sub class_cat {
    my $env = shift;
    my $dbh = $db->get_dbh();

    my $req = new Plack::Request($env);
    my $param = $req->parameters();
    my ($lang) = ($param->{'lang'} || 'nl' =~ m/(nl|fr)/);

    my $sql = qq/
    select cat,
            count(*) as count,
            array_agg(docuid) as docuids
     from (select cat, unnest(docuids) as docuid from __staatsblad_${lang}_docuid_per_cat) as foo
     where docuid in (select docuid from staatsblad_$lang where plainto_tsquery('public.belaws_$lang',?) @@ fts)
     group by cat order by count desc/;

    my $rows = $dbh->selectall_arrayref($sql, {Slice=>{}},$param->{'q'});

    return [ 200, [ 'Content-Type' => 'application/json; charset=utf-8' ], [ encode_json($rows) ] ];
};

sub class_geo {
    my $env = shift;
    my $dbh = $db->get_dbh();

    my $req = new Plack::Request($env);
    my $param = $req->parameters();
    my ($lang) = ($param->{'lang'} || 'nl' =~ m/(nl|fr)/);

    my $sql = qq/
    select geo,
            count(*) as count,
            array_agg(docuid) as docuids
     from (select geo, unnest(docuids) as docuid from __staatsblad_${lang}_docuid_per_geo) as foo
     where docuid in (select docuid from staatsblad_$lang where plainto_tsquery('public.belaws_$lang',?) @@ fts)
     group by geo order by count desc/;

    my $rows = $dbh->selectall_arrayref($sql, {Slice=>{}},$param->{'q'});

    return [ 200, [ 'Content-Type' => 'application/json; charset=utf-8' ], [ encode_json($rows) ] ];
};


sub doc {
    # get main actors: the PSGI environment and the database handler
    my $env = shift;
    my $dbh = $db->get_dbh();

    # get the HTTP request parameters into a Hash::Multivalue ref
    my $req = new Plack::Request($env);
    my $param = $req->parameters();

    # validate incoming variables of which docuid is required
    my ($lang) = ($param->{'lang'} || 'nl' =~ m/(nl|fr)/);
    my ($query) = ($param->{'q'} || '' =~ m/^((?:\w+\ )+)/);
    my ($icols) = ($param->{'attr'} || '' =~ m/(\w+(?:\s*,\s*\w+)*)/);
    my ($docuid) = ($param->{'docuid'} || '' =~ m/^(\d{4}-\d{2}-\d{2}\/\d{2})$/)
                    or return [ 500, [ 'Content-Type' => 'text/plain' ], [ 'docuid is malformed' ] ];

    # sql querystring munging, used if query is defined to hilight the matches from within the db
    my $qq = $dbh->quote($query);
    my $dict = 'public.belaws_'.$lang;
    my $opts = 'StartSel="<em class=hl>", StopSel=</em>, HighlightAll=TRUE';

    # a map of key => sql column expressions as to be able to dynamically alter the ones used
    my $colmap = {
        body => $query ? "ts_headline('$dict',body, plainto_tsquery('$dict',$qq), '$opts') as body" : 'body',
        title => $query ? "ts_headline('$dict',title, plainto_tsquery('$dict',$qq), '$opts') as title" : 'title',
        map { $_ => $_ } (qw/docuid plain pubid pubdate source pages effective pretty/)
    };

    # map list of selected cols (icols or all keys of colmap) into a hash columnexpressions (no dupes). body is always selected
    my %cols = map { $colmap->{$_} => 42 } ($icols ? split /\s*,\s*/, $icols : keys %$colmap), 'body' ;


    # start of processing, main sql query ###############################################################################################

    my $row = $dbh->selectrow_hashref("select ". join(',', keys %cols)  ." from staatsblad_$lang where docuid = ? limit 1",undef,$docuid);

    # format the body into a prettyfied html body TODO: cache in db
    $row->{pretty} = BeLaws::Format::ejustice_fgov::prettify($row->{body}, $lang, $docuid) if exists $cols{pretty};

    # delete the body if it was not requested
    delete $row->{body} if $icols && $icols !~ m/body/;

    # return the result in utf-8 encoded json
    return [ 200, [ 'Content-Type' => 'application/json; charset=utf-8' ], [ encode_json($row) ] ];
};


sub check_raadvanstate {
    my $env = shift;
    my $dbh = $db->get_dbh();

    my $req = new Plack::Request($env);
    my $param = $req->parameters();
    my $res;

    my ($pubid) = ($param->{'pubid'} =~ m/^\d+$/) 
                    or return [ 500, [ 'Content-Type' => 'text/plain' ], [ 'pubid is malformatted' ] ];

    # lookup data on raadvanstate #############################################################################################################

    eval { $res = BeLaws::Query::raadvanstate->new->request($pubid) };

    my @log_uid = ('raadvanstate', 'nl', $pubid );

    if($@) { $dbh->do('insert into x_fetchlog (name, lang, key, status, val) values (?, ?, ?, ?, ?)',undef, @log_uid, 'fail',$@) }
    my ($val) = $dbh->selectrow_array("select val from x_fetchlog where status = 'ok' and name = ? and lang = ? and key = ?", undef, @log_uid, $pubid);


    # update or insert
    my $doc = $dbh->selectrow_hashref("select * from raadvanstate_nl docuid = ?",{},$pubid);
    if(not defined $doc->{numac}) {
        warn "inserting NEW $pubid";
        my @cols = (qw/id numac kind datum starts ends title/);
        $dbh->do('insert into staatsblad_nl ('.join(',',@cols).') values ('.join(',',map { '?' } @cols).')',undef, @{$doc}{@cols})
            and $dbh->do('insert into x_fetchlog (name, lang, key, status, val) values (?, ?, ?, ?, ?)',undef, @log_uid, 'ok', encode_json($res) );
    } else {
        warn "seen $pubid with recency ".$doc->{recency};
        if($res != $val) {
            warn "current and previous result differ";
            warn "$res";
            warn "$val";
        }
    }
    return [ 200, [ 'Content-Type' => 'application/json; charset=utf-8' ], [ encode_json({juridat => $res} ) ] ];

    # my $cvl = new BeLaws::Spider::codex_vlaanderen();
    # my $res3 = $cvl->request($mbid);

    # my $codex = $dbh->selectrow_hashref('select * from codex_vlaanderen_nl where docuid = ?',{},$docuid);
    # unless(defined $codex->{id}) {
        # warn "inserting NEW";
        # my @cols = (qw/docuid title body plain pubid pubdate source pages pdf_href effective/);
        # $dbh->do('insert into staatsblad_nl ('.join(',',@cols).') values ('.join(',',map { '?' } @cols).')',undef, @{$codex}->{@cols});
    # }

    # return [ 200, [ 'Content-Type' => 'application/json; charset=utf-8' ], [ encode_json({staatsblad => $res, raadvanstate => $res2, codex_vlaanderen => $res3 } ) ] ];
};


sub check_juridat {
    my $env = shift;
    my $dbh = $db->get_dbh();

    my $req = new Plack::Request($env);
    my $param = $req->parameters();

    my ($docuid) = ($param->{'id'} =~ m/^(\d+)$/) 
                    or return [ 500, [ 'Content-Type' => 'text/plain' ], [ 'id is malformatted' ] ];

    warn "docuid is ".$docuid;

    # did we fetch it today ? ifso return 500
    # scalar $dbh->selectrow_array('select * from juridat_status_nl where id = ?',undef, $docuid)
        # and return [ 500, [ 'Content-Type' => 'application/json; charset=utf-8' ], [ encode_json({ op => 'noop', msg => 'has already been fetched' }) ] ];

    my $id = $docuid; 

    warn '$id: %o', $id;

    my $beq = new BeLaws::Query::juridat();
    my $res = $beq->request($id);

    return [ 200, [ 'Content-Type' => 'application/json; charset=utf-8' ], [ encode_json({juridat => $res} ) ] ];
    # return [ 200, [ 'Content-Type' => 'text/xml; charset=utf-8' ], [ encode('utf8',$res) ] ];
};

sub stats_person_party {
    my $env = shift;
    my $dbh = $db->get_dbh();

    my $req = new Plack::Request($env);
    my $param = $req->parameters();

    my $sql = "select name as nodeName, party as group from _person_per_party order by party asc";

    my $rows = $dbh->selectall_arrayref($sql, {Slice=>{}});

    map { $_->{nodeName} = $_->{nodename}; delete $_->{nodename} } @$rows;

    return [ 200, [ 'Content-Type' => 'application/json; charset=utf-8' ], [ encode_json($rows) ] ];
};

sub stats_person_cosign {
    my $env = shift;
    my $dbh = $db->get_dbh();

    my $req = new Plack::Request($env);
    my $param = $req->parameters();

    my $sql = 'select * from _person_cosign_link where value > 0 order by value desc';

    my $rows = $dbh->selectall_arrayref($sql, {Slice=>{}});

    return [ 200, [ 'Content-Type' => 'application/json; charset=utf-8' ], [ encode_json($rows) ] ];
}
sub word_trends_per_month {
    my $env = shift;
    my $dbh = $db->get_dbh();

    my $req = new Plack::Request($env);
    my $param = $req->parameters();

    my $sql = 'select * from _word_trends_per_month';

    my $rows = $dbh->selectall_arrayref($sql, {Slice=>{}});

    return [ 200, [ 'Content-Type' => 'application/json; charset=utf-8' ], [ encode_json($rows) ] ];
    
}





42;
