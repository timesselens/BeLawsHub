package BeLaws::Format::ejustice_fgov;
use common::sense;
use Carp qw/croak/;
use Web::Scraper;
use HTML::Tidy;
use Data::Dumper;
use Encode;
#use Data::Dumper::HTML qw(dumper_html);


sub prettify {
    my $html = shift;
    my ($lang) = (shift =~ m/^(nl|fr)$/);
    my ($docuid) = (shift =~ m/^(\d{4}-\d{2}-\d{2}\/\d{2})$/);
    $lang ||= 'nl';

    # fix invalid comma in td
    $html =~ s/<td([^>,]*),?([^>]*)>/<td $1$2>/gsm;
    # fix non html tags in <>
    # $html =~ s/<(Voor[^>]+)>/$1/gsm;
    $html = HTML::Tidy->new->clean($html);
    # warn '$html: %o', $html;

    $html =~ s@<td align=left , width=100%>@<td>@g;

    my $s = scraper {
        process 'table[bgcolor="#bcd9ff"]', "meta_tables[]" => scraper {
            process 'a' => 'links[]' => { text => 'TEXT', link => '@href' };
        };
        process 'table[bordercolor="black"]', 'tables[]' => 'HTML';
    };

    my $res = $s->scrape($html);

    my @inhoudlinks;

    while ($res->{tables}->[2] =~ m#<a\s*href="([^"]+)" name="[^"]+">([^<]+)</a>[\s_\-]*([^<]+)<br />#gioms) {
        push @inhoudlinks, [$1,$2,$3];
    }

    my $s2 = scraper {
        process 'th', 'heads[]' => 'HTML';
    };

    my $res2 = $s2->scrape($res->{tables}->[3]);

    my $text = $res2->{heads}->[3];

    # try and replace references to internal article references
    sub to_article {
        my ($id, $art, $text, $lang,$docuid) = @_;
        my $anchor = $id;
        $id =~ s/^\s|\s$//go;
        $id =~ s/\W/_/go;
        $id =~ s/_+/_/go;
        $id = lc $id;
        $text =~ s/^[\.\ ]+//go;
        $text =~ s/<br \/><br \/>\s*$/\n\n/io;
        $text =~ s/----------/<hr>/g;

        my ($anchor_n) = ($anchor =~ m/^Art\.(.*)$/);
        if($text =~ m/^$anchor_n\.\ /) { $art = $anchor_n; $text =~ s/^$anchor_n\.\ //; }

        my $finaltext = "";
        my @lines = split />.*?\K(§\ ?\d+\.)/,$text;
        my $paropen = 0;
        for my $line (@lines) {
            if($line =~ m/^§\ \d+./) {
                $finaltext .= '</p>' if $paropen;
                $finaltext .= "<p>$line";
                $paropen = 1;
            } else {
                $finaltext .= $line;
            }
        }
        $finaltext .= '</p>' if $paropen;
        $finaltext = "<p>$finaltext</p>" if not $paropen;

        return "\n<section id=\"$id\"><span class=\"art\"><a name=\"$anchor\" href=\"/$lang/$docuid/$id\">Art $art</a></span>$finaltext</section>\n";
    }

    $text =~ s@<a(?: href="[^"]+")? name="(Ar[^"]+)">[^<]+</a>\s*(?:<a\s*href="[^"]+">([^<]+)</a>)?(.*?)(?=(?:$|Brussel, \d+|<br /><br />[\s\t]*<a href="#L|<a href="#\1" name="[^"]+">))@to_article($1,$2,$3,$lang,$docuid)@gie;
    $text =~ s@<a href="[^"]+" name="([^"]+)">([^<]+)\.?</a>\s*_?\s*(.*?)<br \/><br \/>@<h1><a name="$1" href="#$1">$2</a> $3</h1>@gi;

    $text =~ s@<a href="/cgi_loi/change_lg\.pl\?language=(nl|fr)&amp;la=N&amp;table_name=wet&amp;cn=(\d{4})(\d{2})(\d{2})(\d{2})"@<a href="/$1/$2-$3-$4/$5/"@g;



    # try and replace docuid references
    sub to_link {
        my ($type, $docuid, $ref, $start, $lang) = @_;
        my $class = lc $type;
           $class =~ s/ingevoegd bij\s*//io;
           $class =~ s/^\s*|\s*$//gio;
           $class =~ s/^w$/wet/gio;

           $type =~ s/^w$/Wet/gio;

        return "<span class=\"ref\"><span class=\"$class\">&laquo;</span><span class=\"type\">$type</span> <a title=\"inwerkingstreding $start\" href=\"/$lang/$docuid#Art.$ref\">$docuid#Art.$ref</a><span class=\"start\">Inwerkingtreding: $start</span><span class=\"$class\">&raquo;</span></span>";
    }

    $text =~ s@(?:&#60;|&lt;)\s*((?:Ingevoegd bij)?\s*(?:W|wet|KB|MB)).*?(\d{4}\W*\d{2}\W*\d{2}\/\d{2}).*?art\w*\.?\s*([\d\.\w]+).*?Inwerkingtreding.*?\s*(onbepaald\s*|(?:onbepaald en uiterlijk op\s*)?\s*\d{2}\W*\d{2}\W*\d{4})\s*(?:&#62;|&gt;)@to_link($1,$2,$3,$4,$lang)@gie;

    
    my @match = ($text =~ m@&#60;(W|wet|KB|MB)\s*(\d{4}\W*\d{2}\W*\d{2}\/\d{2}).*?art\w*\.?\s*([\d\.\w]+).*?Inwerkingtreding.*?(\d{2}\W*\d{2}\W*\d{4})&#62;@gi);

    my $reformed = [
        '<style>',
            'div.toc { margin-left: 1em; border-left: 10px solid #ddd; margin-bottom: 2em; }',
            'div.toc ul { margin:0; padding:0 }',
            'div.toc ul li { list-style: none; margin:0; padding:0; margin-left: 0.5em; }',
            'div.toc ul li a { padding: 0.2em 0.5em; text-decoration: none; color: black; display: block; border-left: 5px solid transparent; }',
            'div.toc ul li a:hover { border-left: 5px solid yellowgreen; background: #feffef; }',
            'div.toc ul li a span { margin-right: 1em; font-weight: bold; font-variant: small-caps; }',
            'div.toc ul li a em {  }',
            'div.law h1 { font-size: 2.0em; font-variant: small-caps; color: #444; margin-left: 0.5em; line-height: 1.5em;}',
            'div.law h1 a { text-decoration: none; color: #444; border-bottom: 1px dashed grey; }',
            'div.law section { margin: 1em; padding: 1em; border: 1px dotted lightgrey; -moz-border-radius: 5px; -webkit-border-radius: 5px; min-height: 55px;}',
            'div.law section span.art a { color: black; text-decoration: none; }',
            'div.law section span.art { background-color: hsl(60, 100%, 82%); font-size: 2.0em; font-family: Tahoma; margin-top: 3px;',
                                         'padding: 0 10px 0 15px; -moz-border-radius: 5px 0 0 0; -webkit-border-radius: 5px 0 0 0; line-height: 140%;',
                                         'border: 1px solid hsl(43, 74%, 76%); display: inline; float: left; margin-right: 0.5em; }',
            'div.law section p { font-family: Georgia, Serif; line-height: 155%; font-size: 1.1em; margin: 0;}',
            'div.law span.ref { background-color: #feffef; padding: 4px 0}',
            'div.law span.wet { color: orange; font-weight: bold; }',
            'div.law span.kb { color: yellowgreen; font-weight: bold; }',
            'div.law span.ref span.start { display: none; }',
            'div.law section table { margin: 1em; border: 1px solid #666; font-family: monospace; }',
            'div.law section table tr { border-bottom: 1px solid #999 }',
            'div.law section table tr:nth-child(odd) { background-color: #ccc }',
            'div.law section table tr td { padding: 0.2em 0.5em; }',
            'div.law section table tr td { border-right: 1px dashed #aaa }',
        '</style>',
        '<div class="toc">',
            '<ul>',
                (map { "<li><a href=" . $_->[0] . "><span>" . $_->[1] . "</span><em>" . $_->[2] . "</em></a></li>"; } @inhoudlinks),
            '</ul>',
        '</div>',
        '<div class="main law">',
            $text,
        '</div>',
    ];

    $html = undef;

    return join '',@$reformed;
}

42;
