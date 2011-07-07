package BeLaws::API::Staatsblad;
use strict;
use warnings;
use Carp qw/croak/;
use BeLaws::Driver::Storage::PostgreSQL;
use JSON::XS;
use Plack::Request;
use BeLaws::Query::ejustice_fgov::document;
use BeLaws::Query::ejustice_fgov::kind;
use BeLaws::Format::ejustice_fgov;
use Data::Dumper;
use Text::Diff;
use Encode qw/decode encode/; 
use Capture::Tiny qw/capture/;
use Test::Builder;
use HTTP::Exception; sub throw { HTTP::Exception->throw(shift,status_message => shift) };

# return a list of docuids parsed from the db
sub seed {#{{{
    my $dbh = $db->get_dbh;
    my $docuids = $dbh->selectcol_arrayref('select docuid from __staatsblad_nl_docuid_in_body order by random() limit 10');
    return [ 200, [ 'Content-Type' => 'application/json' ], [ encode_json($docuids) ] ];
};#}}}

sub fetch {#{{{
    my $env = shift;
    my $dbh = $db->get_dbh();

    my $req = new Plack::Request($env);
    my $param = $req->parameters();
       $param->{'lang'} ||= 'nl'; # default
    my $res;

    my ($docuid)    = ($param->{'docuid'} =~ m/^(\d{4}-\d{2}-\d{2}\/\d+)$/)     or throw 500, 'docuid is malformatted';
    my ($lang)      = ($param->{'lang'} =~ m/^(nl|fr|de)$/)                     or throw 500, 'lang is malformatted';

    my $drv = new BeLaws::Driver::LWP;
    my $httpreq = BeLaws::Query::ejustice_fgov::document->new(language => $lang)->make_request(cn => $docuid); 
    my $resp = $drv->process($httpreq);
    my $cont = encode('utf8',$resp->decoded_content());

    my $result = {
        docuid => $docuid,
        lang => $lang,
        status_code => 200,
        status => 'FETCHED',
        message => 'document has been correctly fetched from source',
        see_also => [
            "http://".$env->{HTTP_HOST}."/api/internal/parse/staatsblad.json?docuid=$docuid&lang=$lang",
            "http://".$env->{HTTP_HOST}."/api/internal/format/staatsblad.json?docuid=$docuid&lang=$lang",
            "http://".$env->{HTTP_HOST}."/api/internal/resolve/staatsblad.json?docuid=$docuid&lang=$lang",
            "http://".$env->{HTTP_HOST}."/api/internal/test/staatsblad.json?docuid=$docuid&lang=$lang",
            "http://".$env->{HTTP_HOST}."/api/internal/info/staatsblad.json?docuid=$docuid&lang=$lang" ],
    };

    eval { $dbh->do('insert into incoming (parser, uid, lang, body) values (?, ?, ?, ?)',undef,'BeLaws::Query::ejustice_fgov', $docuid, $lang, $cont) };

    if ($@) {
        $result->{status_code} = 500;
        $result->{status} = 'error';
        $result->{message} = 'there has been a database error, please consult the logfiles';
    }

    if ($@ =~ m/tried to insert same body/) {
        $result->{status_code} = 420; 
        $result->{status} = 'deferred';
        $result->{message} = 'incoming queue already has a row with this exact content, discarding...';
    }

    return [ $result->{status_code}, [ 'Content-Type' => 'application/json' ], [ encode_json($result) ] ];
};#}}}

sub resolve {#{{{
    my $env = shift;
    my $dbh = $db->get_dbh();

    my $req = new Plack::Request($env);
    my $param = $req->parameters();
       $param->{'lang'} ||= 'nl'; # default
    my $res;

    my ($docuid)    = ($param->{'docuid'} =~ m/^(\d{4}-\d{2}-\d{2}\/\d+)$/)     or throw 500, 'docuid is malformatted';
    my ($lang)      = ($param->{'lang'} =~ m/^(nl|fr|de)$/)                     or throw 500, 'lang is malformatted';

    my $drv = new BeLaws::Driver::LWP;
    my $q = new BeLaws::Query::ejustice_fgov::kind;
    my $kind = "";

    my @kinds = ('koninklijk besluit','ministrieel besluit','wet','besluit','collectieve arbeidsovereenkomst',
        # 'algemeen reglement arbeidsbescherming', 'arrest arbitragehof', 'arrest grondwettelijk hof',
        # 'besluit (brussel)', 'besluit duitstalige gemeenschap', 'besluit franse gemeenschap',
        # 'besluit vlaamse executieve', 'besluit vlaamse regering', 'besluit waalse gewest',
        # 'besluitwet', 'boswetboek', 'brussels gemeentelijk kieswetboek',
        # 'brussels wetboek van ruimtelijke ordening', 'burgerlijk wetboek', 'collectieve arbeidsovereenkomst',
        # 'decreet (brussel)', 'decreet duitstalige gemeenschap', 'decreet franse gemeenschap', 'decreet vlaamse raad',
        # 'decreet waalse gewest', 'eeg-richtlijn', 'eeg-verdrag', 'eeg-verordening', 'ega-verdrag',
        # 'egks-verdrag', 'gemeentewet', 'gerechtelijk wetboek', 'grondwet 1831', 'grondwet 1994', 'huisvestingscode',
        # 'indexcijfer', 'kieswetboek', 'militair strafwetboek', 'militair wetboek van strafvordering', 'ministeriele omzendbrief',
        # 'ordonnantie (brussel)', 'provinciewet', 'regentsbesluit', 'samenwerkingsakkoord (nationaal)', 'strafwetboek',
        # 'varia', 'veldwetboek', 'verdrag', 'verordening (brussel)', 'vlaamse codex ruimtelike ordening',
        # 'vlaiem', 'waalse ambtenarencode', 'waalse huisvestingscode', 'waalse milieuwetboek',
        # 'waalse wetboek van ruimtelijke ordening, stedebouw, patrimonium en energie', 'wetboek der met het zegel gelijkgestelde taksen',
        # 'wetboek der registratie-, hypotheek- en griffierechten', 'wetboek der successierechten', 'wetboek der zegelrechten',
        # 'wetboek met inkomstenbelastingen gelijkgestelde belastingen', 'wetboek rechtspleging landmacht',
        # 'wetboek van de belasting over de toegevoegde waarde', 'wetboek van de belgische nationaliteit',
        # 'wetboek van de inkomstenbelastingen', 'wetboek van koophandel', 'wetboek van plaatselijke democratie en decentralisatie',
        # 'wetboek van strafvordering', 'wetboek van vennootschappen', 'wet voorlopige hechtenis',
    );

    foreach(@kinds) {
        my $httpreq = $q->make_request(cn => $docuid, dt => $_); 
        my $resp = $drv->process($httpreq);
        my $obj = $q->parse_response($resp,'perl');
        if ($obj->{count}) {
            $kind = $_ ;
            last;
        }
    }

    my $result = {
        docuid => $docuid,
        lang => $lang,
        status_code => 200,
        kind => $kind,
        status => 'RESOLVED',
        message => 'document has been correctly resolved as ['.$kind.']',
        see_also => [
            "http://".$env->{HTTP_HOST}."/api/internal/fetch/staatsblad.json?docuid=$docuid",
            "http://".$env->{HTTP_HOST}."/api/internal/parse/staatsblad.json?docuid=$docuid",
            "http://".$env->{HTTP_HOST}."/api/internal/format/staatsblad.json?docuid=$docuid",
            "http://".$env->{HTTP_HOST}."/api/internal/test/staatsblad.json?docuid=$docuid",
            "http://".$env->{HTTP_HOST}."/api/internal/info/staatsblad.json?docuid=$docuid" ],
    };

    eval { $dbh->do("update staatsblad_$lang set kind = ? where docuid = ?",undef,$kind,$docuid) };

    if ($@) {
        $result->{status_code} = 500;
        $result->{status} = 'error';
        $result->{message} = 'there has been a database error, please consult the logfiles';
        warn $@;
    }

    return [ $result->{status_code}, [ 'Content-Type' => 'application/json' ], [ encode_json($result) ] ];
};#}}}

sub parse {#{{{
    my $env = shift;
    my $dbh = $db->get_dbh();

    my $req = new Plack::Request($env);
    my $param = $req->parameters();
       $param->{'lang'} ||= 'nl'; # default
    my $res;

    # redefine throw

    my ($docuid)    = ($param->{'docuid'} =~ m/^(\d{4}-\d{2}-\d{2}\/\d+)$/)     or throw 500, 'docuid is malformatted';
    my ($lang)      = ($param->{'lang'} =~ m/^(nl|fr|de)$/)                     or throw 500, 'lang is malformatted';


    my $row = $dbh->selectrow_hashref('select * from incoming where parser = ? and lang = ? and uid = ? order by id desc limit 1', {Slice=>{}} ,
                                        'BeLaws::Query::ejustice_fgov', $lang, $docuid) or throw 500, 'unable to get original doc from db, try fetching first';

    throw 404, 'original doc not found' unless $row->{body};

    my $obj = new BeLaws::Query::ejustice_fgov::document->parse_response($row->{body},'sql_row') or throw 500, 'unparsable';
    
    throw($obj->{error}, "parse error: ".$obj->{msg}) if defined $obj->{error};

    my $prev = $dbh->selectrow_hashref('select '.join(',',keys %$obj).' from staatsblad_'.$lang.' where docuid = ?',{Slice=>{}}, $docuid);

    my $result = {
        docuid => $docuid,
        lang => $lang,
        see_also => [
            "http://".$env->{HTTP_HOST}."/api/internal/fetch/staatsblad.json?docuid=$docuid&lang=$lang",
            "http://".$env->{HTTP_HOST}."/api/internal/format/staatsblad.json?docuid=$docuid&lang=$lang",
            "http://".$env->{HTTP_HOST}."/api/internal/test/staatsblad.json?docuid=$docuid&lang=$lang",
            "http://".$env->{HTTP_HOST}."/api/internal/info/staatsblad.json?docuid=$docuid&lang=$lang" ],
        incoming_id => $row->{id},
        incoming_ts => $row->{ts},
    };


    throw (500, 'parsed object had no docuid') unless $obj->{docuid};
    throw (500, 'parsed object had no body') unless $obj->{body};

    my %diff = map { $_ => diff(\($prev->{$_}),\($obj->{$_}), {STYLE => 'Unified'}) } grep { $obj->{$_} ne $prev->{$_} } keys %$obj;
    $result->{diff} = \%diff;

    if(not %diff) {
        $result->{message} = 'document parser gave identical results, disgarding...';
        return [ 200, [ 'Content-Type' => 'application/json; charset=utf-8' ], [ encode_json($result) ] ];
    };

    if(not defined $prev->{docuid}) {
        $dbh->do('insert into staatsblad_'.$lang.' ('.join(',', keys %$obj).') values ('.join(',', map { '?' } keys %$obj ).')', undef, values %$obj)
            or throw (500, 'db error while inserting');
        $result->{message} = 'inserted into staatsblad_'.$lang;
    } else {
        my %upd = %$obj;
        delete $upd{docuid};
        warn 'updated';
        $dbh->do('update staatsblad_'.$lang.' set '.join(',', map { $_ . "= ? "} (keys %upd)).' where docuid = ?', undef, values %upd, $obj->{'docuid'})
            or throw(500, 'db error while updating');
        $result->{message} = 'updated staatsblad_'.$lang;
    };

    return [ 200, [ 'Content-Type' => 'application/json; charset=utf-8' ], [ encode_json($result) ] ];

};#}}}

sub format {#{{{
    my $env = shift;
    my $dbh = $db->get_dbh();

    my $req = new Plack::Request($env);
    my $param = $req->parameters();
       $param->{'lang'} ||= 'nl'; # default
    my $res;

    my ($docuid)    = ($param->{'docuid'} =~ m/^(\d{4}-\d{2}-\d{2}\/\d+)$/)     or throw 500, 'docuid is malformatted';
    my ($lang)      = ($param->{'lang'} =~ m/^(nl|fr|de)$/)                     or throw 500, 'lang is malformatted';


    my $row = $dbh->selectrow_hashref('select body from staatsblad_'.$lang.' where docuid = ?', {Slice=>{}} , $docuid)
                                        or throw 500, 'unable to get body doc from db, try parsing first';

    my $result = BeLaws::Format::ejustice_fgov::prettify($row->{body});

    return [ 200, [ 'Content-Type' => 'text/html' ], [ $result ] ];
    return [ 200, [ 'Content-Type' => 'application/json' ], [ encode_json({ docuid => $docuid, lang => $lang, html => $result }) ] ];
};#}}}

sub info {#{{{
    my $env = shift;
    my $dbh = $db->get_dbh();

    my $req = new Plack::Request($env);
    my $param = $req->parameters();
       $param->{'lang'} ||= 'nl'; # default
    my $res;

    my ($docuid)    = ($param->{'docuid'} =~ m/^(\d{4}-\d{2}-\d{2}\/\d+)$/)     or throw 500, 'docuid is malformatted';
    my ($lang)      = ($param->{'lang'} =~ m/^(nl|fr|de)$/)                     or throw 500, 'lang is malformatted';

    my $info = {
        last_fetched => ($dbh->selectrow_array('select ts from incoming where uid = ? and lang = ?',undef,$docuid,$lang) || []),
        # last_updated => $dbh->selectrow_array('select ts from staatsblad_nl where docuid = ?',undef,$docuid), #has no ts
        last_log => ($dbh->selectall_arrayref('select ts,iid,status,uid from x_process_log where uid = ?',{Slice=>{}},$docuid) || [])
    };

    return [ 200, [ 'Content-Type' => 'application/json' ], [ encode_json($info) ] ];
};#}}}

sub test {#{{{
    my $env = shift;
    my $dbh = $db->get_dbh();

    my $req = new Plack::Request($env);
    our $param = $req->parameters();
        $param->{'lang'} ||= 'nl'; # default
    my $res;

    my ($docuid)    = ($param->{'docuid'} =~ m/^(\d{4}-\d{2}-\d{2}\/\d+)$/)     or throw 500, 'docuid is malformatted';
    my ($lang)      = ($param->{'lang'} =~ m/^(nl|fr|de)$/)                     or throw 500, 'lang is malformatted';

    # setup Test::Builder for test cases in persistent env
    our $t = new Test::Builder;
    our $out = "";
    $t->output(\$out);
    $t->failure_output(\$out);
    $t->todo_output(\$out);

    # define some aliases for later use
    sub ok { $t->ok(@_) }
    sub is { $t->is_eq(@_) }
    sub like { $t->like(@_) }
    sub unlike { $t->unlike(@_) }
    sub response { 
        # reset the test environment
        $t->diag(shift);
        $t->finalize;
        $t->reset;

        # if a parameter json is seen, return it in json instead of TAP
        $param->{json} ? return [ 200, [ 'Content-Type' => 'application/json' ], [ encode_json($t->details) ] ]
                       : return [ 200, [ 'Content-Type' => 'text/plain' ], [ $out ] ];
    }

    # beginning of testcases 
    my $row = $dbh->selectrow_hashref('select * from incoming where parser = ? and lang = ? and uid = ? order by id desc limit 1', {Slice=>{}} ,
                                        'BeLaws::Query::ejustice_fgov', $lang, $docuid);

    # test if the document was fetched
    ok $row->{body}, "incoming table has a body for $docuid"
        or return response('BAILING OUT: incoming table has no body, skipping all other tests');
    unlike $row->{body}, qr/No article available with such references/, "remote side has sent us a real document"
        or return response('BAILING OUT: article not available, skipping all other tests');

    # my $parsed = $dbh->selectrow_hashref("select * from staatsblad_$lang where docuid = ?",undef, $docuid);

    return response()
};#}}}

sub stat {#{{{
    my $env = shift;
    my $dbh = $db->get_dbh();

    my $req = new Plack::Request($env);
    my $param = $req->parameters();

    my $and_maybe_docuids = $param->{include_docuids} ? ", docuids" : "";
    my $stat = $param->{as_hash} ?  
    {
        categories =>  $dbh->selectall_hashref("select count,cat $and_maybe_docuids from __staatsblad_nl_docuid_per_cat", 'cat'),
        persons => $dbh->selectall_hashref("select name,count $and_maybe_docuids from (select name,array_length(staatsblad_nl_ids,1) as count, staatsblad_nl_docuids as docuids from person) as foo",'name'),
        sources => $dbh->selectall_hashref("select count,source $and_maybe_docuids from _staatsblad_nl_source",'source'),
        namedrefs => $dbh->selectall_hashref("select count,named,cat $and_maybe_docuids from _staatsblad_nl_named",'named')
    } 
    :
    {
        categories =>  $dbh->selectall_arrayref("select count,cat $and_maybe_docuids from __staatsblad_nl_docuid_per_cat", {Slice=>{}}),
        persons => $dbh->selectall_arrayref("select name,count $and_maybe_docuids from (select name,array_length(staatsblad_nl_ids,1) as count, staatsblad_nl_docuids as docuids from person) as foo",{Slice=>{}}),
        sources => $dbh->selectall_arrayref("select count,source $and_maybe_docuids from _staatsblad_nl_source",{Slice=>{}}),
        namedrefs => $dbh->selectall_arrayref("select count,named,cat $and_maybe_docuids from _staatsblad_nl_named",{Slice=>{}})
    };
    return [ 200, [ 'Content-Type' => 'application/json' ], [ encode_json($stat) ] ];
};#}}}


42;
