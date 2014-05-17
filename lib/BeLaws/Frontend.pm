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
use HTML::Entities;
use File::Slurp qw/slurp/;
use HTTP::Exception; sub throw { HTTP::Exception->throw(shift,status_message => shift) };
use Encode qw/is_utf8 encode decode/;
use Template::Mustache;
use WebHive::Log qw/warn/;
# use Plack::Middleware::Debug::Panel;

sub doc {
    my $env = shift;
    my $dbh = $db->get_dbh();

    my $req = new Plack::Request($env);
    my $param = $req->parameters();

    my ($docuid) = ($param->{d} =~ m#^(\d{4}-\d{2}-\d{2}/\d{2})$#) or return [ 500, [ 'Content-Type' => 'text/plain' ], [ 'illegal docuid' ] ];
    my ($lang) = ($param->{'lang'} || 'nl' =~ m/(nl|fr)/);

   
    my $sql = qq#select ts_headline('pg',body, plainto_tsquery('public.belaws_$lang',?),'StartSel=\"<em class=hl>\", StopSel=</em>, HighlightAll=TRUE') as body,
                    title, plain, kind
                 from staatsblad_$lang
                 where docuid = ? limit 1#;

    my $row = $dbh->selectrow_hashref($sql ,undef,( $param->{'q'} || '' ),$docuid);

    # build a list of unique words to add them to the description
    my $words = {};
    my @keywords; my $j = 0;
    foreach my $word ($row->{plain} =~ m/([\-\w]+)/g) { next if length($word) <= 10; $words->{$word}++; }
    for my $top (sort { $words->{$b} <=> $words->{$a} } keys %$words) { push @keywords,$top; last if $j++ >= 40; }
    my $keyword_list = join ', ', @keywords;

    my $notfound = qq!
        <em style="font-size: 3em; color: #eee;">404</em> sorry not found in db<br/>
        you can retry fetching the document here: <a href="/try/staatsblad?docuid=$docuid&lang=$lang">/try/staatsblad?docuid=$docuid&lang=$lang</a>!;

    return [ 404, [ 'Content-Type' => 'text/html' ], [$notfound]] unless $row->{body};

    my $result = BeLaws::Format::ejustice_fgov::prettify($row->{body},$lang);
    my $html_title = encode_entities($row->{title});
    $result = qq|<!DOCTYPE html>
        <html>
            <head>
                <title>$html_title</title>
                <meta name="keywords" content="$keyword_list">
            </head>
            <body>
                <h1 class="title" style="font-family: Georgia; background: #e3e3e3; line-height: 200%; padding: 0 1em;">$html_title</h1>
            $result
            </body>
        </html>|;
    return [ 200, [ 'Content-Type' => 'text/html; charset=UTF-8' ], [ is_utf8($result) ? encode('utf8',$result) : $result ] ];
};

sub saved_doc {
    my $env = shift;
    my $dbh = $db->get_dbh();

    my ($year) = ($env->{route}->{year} =~ m/^(\d{4}.?\d{2}.?\d{2})$/);
    my ($no) = ($env->{route}->{no} =~ m/^(\d{2})$/);
    my ($title) = (($env->{route}->{title} || '') =~ m/^([\w\-]*)$/);
    my ($lang) = (($env->{route}->{lang} || 'nl') =~ m/(nl|fr)/);
    my $docuid = "$year/$no";

    $year =~ s/(\d{4}).?(\d{2}).?(\d{2})/$1-$2-$3/;

    return [ 500, [ 'Content-Type' => 'text/plain' ], [ 'error 500' ] ] unless $year && $no && $lang;

    my $sql = qq#select body, title, plain, kind
                 from staatsblad_$lang
                 where docuid = ? limit 1#;

    my $row = $dbh->selectrow_hashref($sql ,undef,$docuid);
    
    my $idtitle = lc decode_entities($row->{title});
    $idtitle =~ s/[^a-z0-9]+/-/g;
    $idtitle =~ s/--/-/g;
    $idtitle =~ s/^-|-$//g;
    $idtitle = substr($idtitle,0,200);


    my $notfound = qq!
        <em style="font-size: 3em; color: #eee;">404</em> sorry not found in db<br/>
        you can retry fetching the document here: <a href="/api/retry/staatsblad?docuid=$docuid&lang=$lang">/api/retry/staatsblad?docuid=$docuid&lang=$lang</a>!;

    return [ 404, [ 'Content-Type' => 'text/html' ], [$notfound]] unless $row->{body};


    # build a list of unique words to add them to the description
    my $words = {};
    my @keywords; my $j = 0;
    foreach my $word ($row->{plain} =~ m/([\-\w]+)/g) { next if length($word) <= 10; $words->{$word}++; }
    for my $top (sort { $words->{$b} <=> $words->{$a} } keys %$words) { push @keywords,$top; last if $j++ >= 40; }
    my $keyword_list = join ', ', @keywords;

    if(-e "./static/$lang/$year/$no/$idtitle.html") {
        return [ 200, [ 'Content-Type' => 'text/html; charset=UTF-8' ], [ slurp("./static/$lang/$year/$no/$idtitle.html") ] ];
    } else {
        my $result = BeLaws::Format::ejustice_fgov::prettify($row->{body},$lang);
        my $html_title = encode_entities(decode_entities($row->{title}));
        warn '$html_title: %o', $html_title;
        $result = qq|<!DOCTYPE html>
            <html>
                <head>
                    <title>$html_title</title>
                    <meta name="keywords" content="$keyword_list" />
                </head>
                <body>
                    <h1 class="title" style="font-family: Georgia; background: #e3e3e3; line-height: 200%; padding: 0 1em;">$html_title</h1>
                $result
                </body>
            </html>|;
        -d "./static/$lang" || mkdir "./static/$lang";
        -d "./static/$lang/$year" || mkdir "./static/$lang/$year";
        -d "./static/$lang/$year/$no" || mkdir "./static/$lang/$year/$no";
        open my $fh, ">:encoding(UTF-8)", "./static/$lang/$year/$no/$idtitle.html";
        binmode($fh);
        print $fh encode('utf8',$result);
        close $fh;
        return [ 200, [ 'Content-Type' => 'text/html; charset=UTF-8' ], [ is_utf8($result) ? encode('utf8',$result) : $result ] ];
    }

}

sub search {
    my $env = shift;
    
    # inline call fwd to API
    my $rows = BeLaws::API::search($env, 1);

    $env->{templhash}->{rows} = $rows;

    $env->{templhash}->{norows} = {} if scalar @$rows == 0;

    return [ 200, [ 'Content-Type' => 'text/html' ] ];

};

sub index {
    return [ 200, [ 'Content-Type' => 'text/html' ] ];
}


42;
