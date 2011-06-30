package BeLaws::Spider::codex_vlaanderen;
use strict;
use warnings;
use Carp qw/croak/;
use HTTP::Request;
use HTTP::Response;
use BeLaws::Driver::LWP;
use JSON::XS;
use Data::Dumper;
use HTML::Strip;
use WWW::Mechanize;
use File::Slurp qw/slurp/;

###############################################################################
# Author: Tim Esselens <tim.esselens@gmail.com> (c) 2011 iRail vzw/asbl [AGPL]
###############################################################################

sub new {
    my $class = shift;
    my $self = {};
    $self->{base} = "http://codex.vlaanderen.be";
    $self->{url}  = "/ALLESNL/wet/zoek.vwp";
    $self->{params} = {
        db => 'CODEX',
    };
    return bless ($self, $class);
}

sub make_request {
    my $self = shift;
    my %attr = ref $_[0] eq 'HASH' ? %{$_[0]} : @_; # so both `f({a=>1})` and `f(a=>1)` are allowed

    croak 'numac is a required argument' unless defined $attr{numac};
    croak 'numac illegal format' unless $attr{numac} =~ m/^\d+$/;

    my $url = $self->{base} .
              $self->{url} . 
              '?' . join '&', ( 'numac='.$attr{numac}, (map { $_.'='.$self->{params}->{$_} } keys %{$self->{params}}));

    my $req = new HTTP::Request(GET => $url);

    return $req;

}

sub request {
    my ($self, $docid, $format) = @_;

    my $mech = WWW::Mechanize->new(agent => 'Mozilla/4.0 (compatible; MSIE 7.0; Windows NT 6.0)', cookie_jar => {});
    my $req = $self->make_request(numac => $docid);
    # my $resp = $drv->process($req);
    # my $ret = $self->parse_response($resp, $format);

    warn $req->url();
    $mech->get($req->url());
    $mech->follow_link(url_regex => qr/lijstform\.vwp/i);
    # detailframe.vwp? infoframe.vwp WetID=1018308
    my ($wetid) = ($mech->content() =~ m/WetID=(\d+)/);
    $mech->follow_link(url_regex => qr/detailframe\.vwp/i);
    # $mech->follow_link(url_regex => qr/infoframe\.vwp/i); $mech->follow_link(url_regex => qr/infoform\.vwp/i);
    my $info = $mech->content;
    
    $mech->get("http://212.123.19.141/ALLESNL/wet/preview.vwp?sid=0&WetID=$wetid&PreviewMode=1");
    my $html = $mech->content();

    my ($title) = ($html =~ m#<FONT color='white'>([^<]+)</FONT>#io);
    my @art = split /<font size="-1" face="Arial,Helvetica,Geneva,Swiss,SunSans-Regular">/, $html;

    my $form = shift (@art) . join "\n", map { "<article>\n$_</article>\n\n" } @art;

    sub strip { my $x = shift; $x =~ s/[\W\s]/_/go; $x =~ s/_+/_/go; $x =~ s/_$//; return lc $x; }
    $form =~ s/<article>[\r\n\s]+<B>([^<]+)<\/B>/"<article id=\"" . strip($1 || "art_0") . "\" ref=\"$1\"><em>$1<\/em>"/gsmei;

    $form =~ s/^.*?<article/<article/smio;
    $form =~ s/<\/(html|body)>//gio;

    # $form =~ s/<br>([^<\n\r]+)[\r\n]*<br>/\n<p>$1<\/p>\n\n/gsmi;

    my $obj = {
        title => $title,
        wetid => $wetid,
        body => $form,
        # info => $info,
        plain => HTML::Strip->new()->parse($form),
    };


    # return unless defined $obj->{docuid};

    $format ||= 'perl';

    for ($format) {
        /html/i and return $html;
        /perl/i and return $obj;
        /json/i and return encode_json($obj);
    }

    return $html; # fallback html
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
