package BeLaws::Query::ejustice_fgov::document;
use strict;
use warnings;
use Carp qw/croak/;
use HTTP::Request;
use HTTP::Response;
use BeLaws::Driver::LWP;
use JSON::XS;
use Data::Dumper;
use Encode;
use HTML::FormatText;
use File::Slurp qw/slurp/;

###############################################################################
# Author: Tim Esselens <tim.esselens@gmail.com> (c) 2011 iRail vzw/asbl [AGPL]
###############################################################################

sub new {
    my $class = shift;
    my %attr = ref $_[0] eq 'HASH' ? %{$_[0]} : @_; # so both `f({a=>1})` and `f(a=>1)` are allowed
    my $self = {};
    my $lang = (($attr{language} || '') =~ m/fr|french|fran?ais/) ? 'F' : 'N';

    $self->{base} = "http://www.ejustice.just.fgov.be";
    $self->{url}  = "/cgi_loi/loi_a1.pl";
    $self->{params} = {
        caller      => 'list',
        la          => $lang,
        sql         => "dt+not+contains+'uniquestringwhichisnotfoo'",
        language    => $lang eq 'N' ? 'nl' : 'fr', 
        chercher    => 't',
        fromtab     => $lang eq 'N' ? 'wet_all' : 'loi'
    };

    return bless ($self, $class);
}

sub make_request {
    my $self = shift;
    my %attr = ref $_[0] eq 'HASH' ? %{$_[0]} : @_; # so both `f({a=>1})` and `f(a=>1)` are allowed

    croak 'cn is a required argument' unless defined $attr{cn};
    $attr{cn} =~ s/\W//gio; # convert 2010-13-03/23 into 2010031323
    croak 'cn is malformed' unless $attr{cn} =~ m/^\d+$/;

    my $url = $self->{base} .
              $self->{url} . 
              '?' . join '&', ( 'cn='.$attr{cn}, (map { $_.'='.$self->{params}->{$_} } keys %{$self->{params}}));

    my $req = new HTTP::Request(GET => $url);

    return $req;

}

sub parse_response {
    my ($self, $in, $dataType) = @_;
    $dataType ||= 'perl';

    my $html = ref $in eq 'HTTP::Response' ? encode('utf-8',$in->decoded_content()) :
                $in !~ m/\n/ && -e $in ? slurp($in) :
                $in;    

    return { error => 404, msg => 'remote side sais document not found' } if ($html =~ m#No article available with such references#);

    my ($dossiernr) = ($html =~ m#<font color=Red>\s*<b>\s*(?:Dossiernummer|Dossier num&eacute;ro)\s*:\s*</b>\s*</font>\s*([^<]+)\s*#smio);

    return { error => 500, msg => 'unable to parse dossiernummer/dossier numero from document' } unless $dossiernr;

    my ($date,$title) = ($html =~ m#<th align\s*=\s*left\s*width=100%>\n</b><b>\s*([^\-]+)\s*\.\s*\-\s*([^<]+)\s*#smio);
    my ($bron) = ($html =~ m#<font color=Red>\s*<b>\s*(?:Bron|Source)\s*:\s*</b></b>\s*</font>\s*([^<]+)\s*#smio);
    my ($pub) = ($html =~ m#<font color=Red>\s*<b>\s*(?:Publicatie|Publication)\s*:\s*</b>\s*</font>\s*([\d\-]+)\s*#smio);
    my ($num) = ($html =~ m#<font color=red>\s*(?:nummer|num&eacute;ro)\s*:\s*</font>\s*([^<]+)\s*#smio);
    my ($blz) = ($html =~ m#<font color=red>\s*(?:bladzijde|page)\s*:\s*</font>\s*(\d+)\s*#smio);
    my ($pdf_href) = ($html =~ m#<a href=([^\s]+) target=_parent>(?:BEELD|IMAGE)</a>#smio);
    my ($inwerking) = ($html =~ m#<font color=Red>\s*<b>\s*(?:Inwerkingtreding|Entr&eacute;e\s*en\s*vigueur)\s*:\s*</b>\s*</font>\s*([\w\-]+)\s*#smio);
    my ($raadvanstate) = ($html =~ m#(http://www.raadvst-consetat.be/refLex/docs/[^\ ']+)#smio);

    # split
    my ($pdf_page) = ($pdf_href =~ m/pdf_page=(\d+)/);
    my ($pdf_link) = ($pdf_href =~ m/pdf_file=([^\ ]+)/);

    my ($docdate) = ($dossiernr =~ m/(\d{4}-\d{2}-\d{2})/);

    if ($pub =~ m/(\d{2})-(\d{2})-(\d{4})/) { $pub = "$3-$2-$1" }

    # cleanup 
    $title =~ s/[\r\n]*//g;
    
    # just for fun: (jan|feb|maart|april|mei|jun|jul|aug|sept|okt|nov)(uar|ustus|o|em|)(i|ber) :-| you see the git change? better type it full
    $title =~ s/^\s*\d+\s*(januari|februari|maart|april|mei|juni|juli|augustus|september|oktober|novemeber|december)\s*\d+\.?\s*\-?\s*//i;
    $title =~ s/^\s*\d+\s*(janvier|f?vrier|mars|avril|mai|juin|juillet|ao?t|septembre|octobre|novemebre|decembre)\s*\d+\.?\s*\-?\s*//i;
    $num =~ s/&nbsp;//g;
    $bron =~ s/^\s*|\s*$//g;
  
    my $formatter = new HTML::FormatText();
    my $obj = {
        date => $date,
        title => $title,
        source => $bron,
        docdate => $docdate,
        pubdate => $pub,
        pubid => $num,
        docuid => $dossiernr,
        pages => $blz,
        pdf_link => $pdf_link,
        pdf_page => $pdf_page,
        raadvanstate_link => $raadvanstate,
        effective => $inwerking,
        body => $html,
        plain => $formatter->format_string( $html , leftmargin => 0, rightmargin => 50)
    };

    for ($dataType) {
        /html/i and return $html;
        /perl/i and return { map { $_ => $obj->{$_} } keys %$obj };
        /sql_row/i and return { map { $_ => $obj->{$_} } (qw/title body plain docuid docdate pubid pubdate source pages pdf_link pdf_page effective/) };
        /json/i and return encode_json($obj);
    }

    return $html; # fallback html
}

sub request {
    my ($self, $docid, $format) = @_;

    my $drv = new BeLaws::Driver::LWP;
    my $req = $self->make_request(cn => $docid);
    my $resp = $drv->process($req);
    my $ret = $self->parse_response($resp, $format);

    return $ret;
}

42;

__END__

=head1 NAME

BeLaws::Query - A HTTP request/resonse interface for www.ejustice.just.fgov.be (working title)

=head1 SYNOPSIS

use BeLaws::Query;

my $beq = new BeLaws::Query();
my $response = $beq->request('2010020901','html');

print $response;

=head1 AUTHORS

Tim Esselens <tim.esselens@gmail.com>
