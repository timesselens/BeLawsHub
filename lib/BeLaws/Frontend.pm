package BeLaws::Frontend;
use strict;
use warnings;
use Carp qw/croak/;
use BeLaws::Driver::Storage::PostgreSQL;
use BeLaws::Query::ejustice_fgov::document;
use BeLaws::Format::ejustice_fgov;
use JSON::XS;
use Plack::Request;
use Data::Dumper;
use BeLaws::API;
use HTTP::Exception; sub throw { HTTP::Exception->throw(shift,status_message => shift) };
use Encode qw/is_utf8 encode decode/;
use Template::Mustache;
# use Plack::Middleware::Debug::Panel;

sub doc {
    my $env = shift;
    my $dbh = $db->get_dbh();

    my $req = new Plack::Request($env);
    my $param = $req->parameters();

    my ($docuid) = ($param->{d} =~ m#^(\d{4}-\d{2}-\d{2}/\d{2})$#)
                        or return [ 500, [ 'Content-Type' => 'text/plain' ], [ 'illegal docuid' ] ];
    my ($lang) = ($param->{'lang'} || 'nl' =~ m/(nl|fr)/);

   
    my $sql = join ' ',
                ("select ts_headline('pg',body, plainto_tsquery('public.belaws_$lang',?),'StartSel=\"<em class=hl>\", StopSel=</em>, HighlightAll=TRUE') as body",
                 "from staatsblad_$lang",
                 "where docuid = ? limit 1");

    my $row = $dbh->selectrow_hashref($sql ,undef,( $param->{'q'} || '' ),$docuid);

    # return [302, [Location => "http://localhost:4998/api/internal/fetch/staatsblad.json?docuid=1984-09-20/30"], ['not found']] unless $row->{body};
    # throw 404, 'not found' unless $row->{body};
    return [ 404, [ 'Content-Type' => 'text/html' ], [ '<em style="font-size: 3em; color: #eee;">404</em> sorry not found in our db<br/> developers go here: <a href="/api/internal/fetch/staatsblad.json?docuid='.$docuid.'&lang='.$lang.'>/api/internal/fetch/staatsblad.json?docuid='.$docuid.'&lang='.$lang.'</a>' ] ] unless $row->{body};

    my $result = BeLaws::Format::ejustice_fgov::prettify($row->{body});

    return [ 200, [ 'Content-Type' => 'text/html; charset=UTF-8' ], [ is_utf8($result) ? encode('utf8',$result) : $result ] ];

};

sub search {
    my $env = shift;
    
    # inline call fwd to API
    my $rows = BeLaws::API::search($env, 1);

    $env->{templhash}->{rows} = $rows;

    $env->{templhash}->{norows} = {} if scalar @$rows == 0;




    return [ 200, [ 'Content-Type' => 'text/html' ] ];

};

42;
