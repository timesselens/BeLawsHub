package BeLaws::Frontend;
use strict;
use warnings;
use Carp qw/croak/;
use BeLaws::Driver::Storage::PostgreSQL;
use BeLaws::Query::ejustice_fgov::document;
use BeLaws::Format::ejustice_fgov;
use JSON;
use Plack::Request;
use Data::Dumper;
use BeLaws::API;
use HTML::Entities;
use File::Slurp qw/slurp/;
use HTTP::Exception; sub throw { HTTP::Exception->throw(shift,status_message => shift) };
use Encode qw/is_utf8 encode decode/;
use Template::Mustache;
use WebHive::Log qw/warn/;
use HTML::Query 'Query';
use utf8;
# use Plack::Middleware::Debug::Panel;

sub doc {
    my $env = shift;
    my $dbh = $db->get_dbh();

    my $req = new Plack::Request($env);
    my $param = $req->parameters();

    my ($docuid) = ($param->{d} =~ m#^(\d{4}-\d{2}-\d{2}/\d{2})$#) or return [ 500, [ 'Content-Type' => 'text/plain' ], [ 'illegal docuid' ] ];
    my ($lang) = ($param->{'lang'} || 'nl' =~ m/(nl|fr)/);

   
    my $sql = qq#select ts_headline('public.belaws_$lang',body, plainto_tsquery('public.belaws_$lang',?),'StartSel=\"<em class=hl>\", StopSel=</em>, HighlightAll=TRUE') as body,
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

    my $result = BeLaws::Format::ejustice_fgov::prettify($row->{body},$lang, $docuid);
    my $html_title = encode_entities($row->{title});
    $result = qq|<!DOCTYPE html>
        <html>
            <head>
                <title>$html_title</title>
                <meta name="keywords" content="$keyword_list">
                <link rel="alternate" type="application/json+oembed" href="http://belaws.be/oembed/$lang/$docuid" title="oEmbed Profile" />
            </head>
            <body>
                <h1 class="title" style="font-family: Georgia; background: #e3e3e3; line-height: 200%; padding: 0 1em;">$html_title</h1>
            $result
            </body>
        </html>|;
    return [ 200, [ 'Content-Type' => 'text/html; charset=UTF-8' ], [ is_utf8($result) ? encode('utf8',$result) : $result ] ];
};

sub saved_art_doc {
    my $env = shift;
    my ($year) = ($env->{route}->{year} =~ m/^(\d{4}.?\d{2}.?\d{2})$/);
    my ($no) = ($env->{route}->{no} =~ m/^(\d{2})$/);
    my ($art) = map { lc $_ } (($env->{route}->{art} || '') =~ m/^([a-z0-9\_\-]*)$/i);
    my ($lang) = (($env->{route}->{lang} || 'nl') =~ m/(nl|fr)/);

    if(-e "./static/$lang/$year/$no/$art.html") {
        return [ 200, [ 'Content-Type' => 'text/html; charset=UTF-8' ], [ slurp("./static/$lang/$year/$no/$art.html") ] ];
    } else {
        $env->{NOREDIR} = 1;
        my $res = saved_doc($env);
        if($res->[0] == 200) {
            my $doc = join "\n", @{$res->[2]};
            # wtf? Query does not recognize sections? meh, whatever
            $doc =~ s/<section/<div class="section"/g; $doc =~ s/<\/section/<\/div/g;
            my $q = Query(text => decode('utf8',$doc));
            my ($p) = $q->query("#$art")->as_HTML();
            if($p) {
                open my $fh, ">:encoding(UTF-8)", "./static/$lang/$year/$no/$art.html";
                binmode($fh);
                print $fh qq|<link rel="alternate" type="application/json+oembed" href="http://belaws.be/oembed/$lang/$year/$no/$art" title="oEmbed Profile" />|;
                print $fh qq|<style> div.section { margin: 1em; padding: 1em; border: 1px dotted lightgrey; -moz-border-radius: 5px; -webkit-border-radius: 5px; min-height: 55px;} div.section span.art a { color: black; text-decoration: none; } div.section span.art { background-color: hsl(60, 100%, 82%); font-size: 2.0em; font-family: Tahoma; margin-top: 3px;padding: 0 10px 0 15px; -moz-border-radius: 5px 0 0 0; -webkit-border-radius: 5px 0 0 0; line-height: 140%;border: 1px solid hsl(43, 74%, 76%); display: inline; float: left; margin-right: 0.5em; }div.section p { font-family: Georgia, Serif; line-height: 155%; font-size: 1.1em; margin: 0;} div.section table { margin: 1em; border: 1px solid #666; font-family: monospace; } div.section table tr { border-bottom: 1px solid #999 }div.section table tr:nth-child(odd) { background-color: #ccc } div.section table tr td { padding: 0.2em 0.5em; } div.section table tr td { border-right: 1px dashed #aaa } </style>|;
                print $fh encode('utf8',$p);
                close $fh;
                return [ 200, [ 'Content-Type' => 'text/html; charset=UTF-8' ], [ slurp("./static/$lang/$year/$no/$art.html") ] ];
            } else {
                return [ 404, [ 'Content-Type' => 'text/plain' ], [ 'not found' ] ];
            }
        } else {
            return $res;
        }
    }
}

sub oembed {
    my $env = shift;
    my $dbh = $db->get_dbh();
    my ($year) = ($env->{route}->{year} =~ m/^(\d{4}.?\d{2}.?\d{2})$/);
    my ($no) = ($env->{route}->{no} =~ m/^(\d{2})$/);
    my ($art) = map { lc $_ } (($env->{route}->{art} || '') =~ m/^([a-z0-9\_\-]*)$/i);
    my ($lang) = (($env->{route}->{lang} || 'nl') =~ m/(nl|fr)/);
    my $docuid = "$year/$no";
    my ($title) = $dbh->selectrow_array(qq#select title from staatsblad_$lang where docuid = ? limit 1#,undef,$docuid);

    if($art) {
        my $res = saved_art_doc($env);
        return $res unless $res->[0] == 200;
            my $html = join("",@{$res->[2]});
            my $obj = {
                version => "1.0",
                title => "$title",
                html => qq|<iframe width="100%" height="350px;" frameborder="0" src="http://belaws.be/$lang/$year/$no/$art"></iframe>|,
            };
        return [ 200, [ 'Content-Type' => 'application/json' ], [ to_json($obj,{utf8=>1}) ] ];
    } else {
        my $obj = {
            version => "1.0",
            title => "$title",
            # the iframe class is for onebox which does a silly regex check *sigh*
            html => qq|<div class="iframe">
            <a href="http://belaws.be/$lang/$docuid" style="display: block">
                <img width="30" height="30" src="http://belaws.be/images/belaws_logo_150.png" style="float:left"/>
                <h2 style="color: #333; padding:2px 0 0 40px;">$title</h2>
                <code style="font-size: small; color: #888; background: #ccc; float:right; padding: 0 5px;">
                <span style="display:none">http://</span>belaws<span style="color:#222;">.</span><span style="color:#FFE936">b</span><span style="color:#FF0F21; padding: 0 5px 0 0;">e</span>/<span style="padding: 0 5px;">$lang</span>/<span style="padding: 0 5px">$year</span>/<span style="padding: 0 5px;">$no</span>
                </code>
                <div style="clear:both"></div>
            </a>
            </div>|,
        };
        return [ 200, [ 'Content-Type' => 'application/json' ], [ to_json($obj,{utf8=>1}) ] ];
    }

}

sub saved_doc {
    my $env = shift;
    my $dbh = $db->get_dbh();

    my ($year) = ($env->{route}->{year} =~ m/^(\d{4}.?\d{2}.?\d{2})$/);
    my ($no) = ($env->{route}->{no} =~ m/^(\d{2})$/);
    # my ($title) = (($env->{route}->{title} || '') =~ m/^([\w\-]*)$/);
    my ($lang) = (($env->{route}->{lang} || 'nl') =~ m/(nl|fr)/);
    my $docuid = "$year/$no";
       
    return [ 302, [ 'Content-Type' => 'text/plain', 'Location' => '/'.$lang.'/'.$year.'/'.$no.'/' ], ['redirecting'] ] unless $env->{REQUEST_URI} =~ m/\/$/ || $env->{NOREDIR};

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

    if(-e "./static/$lang/$year/$no/doc.html") {
        return [ 200, [ 'Content-Type' => 'text/html; charset=UTF-8' ], [ slurp("./static/$lang/$year/$no/doc.html") ] ];
    } else {
        my $result = BeLaws::Format::ejustice_fgov::prettify($row->{body},$lang, "$year/$no");
        my $html_title = encode_entities(decode_entities($row->{title}));
        $result = qq|<!DOCTYPE html>
            <html>
                <head>
                    <title>$html_title</title>
                    <meta name="keywords" content="$keyword_list" />
                    <link rel="alternate" type="application/json+oembed" href="http://belaws.be/oembed/$lang/$docuid" title="oEmbed Profile" />
                </head>
                <body>
                    <h1 class="title" style="font-family: Georgia; background: #e3e3e3; line-height: 200%; padding: 0 1em;">$html_title</h1>
                $result
                </body>
            </html>|;
        -d "./static/$lang" || mkdir "./static/$lang";
        -d "./static/$lang/$year" || mkdir "./static/$lang/$year";
        -d "./static/$lang/$year/$no" || mkdir "./static/$lang/$year/$no";
        open my $fh, ">:encoding(UTF-8)", "./static/$lang/$year/$no/doc.html";
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
