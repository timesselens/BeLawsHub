package BeLaws::Format;
use common::sense;
use Carp qw/croak/;
use Web::Scraper;
use Data::Dumper;
use Encode;
#use Data::Dumper::HTML qw(dumper_html);


sub prettify {
    my $html = shift;

  
    my $s = scraper {
        process 'table[bgcolor="#bcd9ff"]', "meta_tables[]" => scraper {
            process 'a' => 'links[]' => { text => 'TEXT', link => '@href' };
        };
        process 'table[bordercolor="black"]', 'tables[]' => 'HTML';
    };

    my $res = $s->scrape($html);

    my @inhoudlinks;

    while ($res->{tables}->[2] =~ m#<a\s*href="([^"]+)" name="[^"]+">([^<]+)</a>\s*-?\s*([^<]+)<br />#gioms) {
        push @inhoudlinks, [$1,$2,$3];
    }

    my $s2 = scraper {
        process 'th', 'heads[]' => 'HTML';
    };

    my $res2 = $s2->scrape($res->{tables}->[3]);

    my $text = $res2->{heads}->[3];

    # TODO: get access to a better structured document, parse that
    # $text =~ s@<a href="#Art.\d" name="Art.\d">Art.</a> <a href="#Art.\d"> (\d+)</a>@<a class="anchor" href="#Art.$1" name="Art.$1">Art. $1</a>@gio;
    # $text =~ s#<a href="Art[^>]+>(.*?)<br /><br />#</p><p>#gsmio;
    # $text = "<p>$text</p>";

    my $reformed = [
        #'<pre>x', Dumper($res->{tables}->[2]), 'y</pre>',
        '<div class="toc">',
            '<ul>',
                (map { "<li><a href=" . $_->[0] . "><span>" . $_->[1] . "</span><em>" . $_->[2] . "</em></a></li>"; } @inhoudlinks),
            '</ul>',
        '</div>',
        '<div class="main">',
            $text,
        '</div>',
    ];

    $html = undef;

    return encode('utf8',(join '',@$reformed));
}

42;
