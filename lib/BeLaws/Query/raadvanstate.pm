package BeLaws::Query::raadvanstate;
use strict;
use warnings;
use Carp qw/croak/;
use HTTP::Request;
use HTTP::Response;
use BeLaws::Driver::LWP;
use JSON::XS;
use Data::Dumper;
use HTML::Strip;
use File::Slurp qw/slurp/;

###############################################################################
# Author: Tim Esselens <tim.esselens@gmail.com> (c) 2011 iRail vzw/asbl [AGPL]
###############################################################################

sub new {
    my $class = shift;
    my $self = {};
    $self->{base} = "http://www.raadvst-consetat.be";
    $self->{url}  = "/refLex/docs/";
    $self->{params} = {
        db => 'chrono',
        lang => 'nl',
    };
    return bless ($self, $class);
}

sub make_request {
    my $self = shift;
    my %attr = ref $_[0] eq 'HASH' ? %{$_[0]} : @_; # so both `f({a=>1})` and `f(a=>1)` are allowed

    croak 'mbid is a required argument' unless defined $attr{mbid};
    croak 'mbid illegal format' unless $attr{mbid} =~ m/^\d+$/;

    my $url = $self->{base} .
              $self->{url} . 
              '?' . join '&', ( 'mbid='.$attr{mbid}, (map { $_.'='.$self->{params}->{$_} } keys %{$self->{params}}));

    my $req = new HTTP::Request(GET => $url);

    return $req;

}

sub parse_response {
    my ($self, $in, $dataType) = @_;

    my $html = ref $in eq 'HTTP::Response' ? $in->decoded_content() : 
                -e $in ? slurp($in) :
                $in;

    my ($title) = ($html =~ m#<h1 id="detail_title">([^<]+)</h1>#smio);
    my ($date) = ($html =~ m#<td><b>Datum van de akte:</b></td>[\r\n\s]*<td>([^>]+)</td>#smio);
    my ($kind) = ($html =~ m#<td><b>Aard van de akte:</b></td>[\r\n\s]*<td>([^>]+)</td>#smio);
    my ($init) = ($html =~ m#<legend>Periode van geldigheid.*?van\s*(\d+/\d+/\d+)[\r\n\s]*tot#smio);
    my ($fini) = ($html =~ m#<legend>Periode van geldigheid.*?van\s*.*?[\r\n\s]*tot\s*(\d+/\d+/\d+)#smio);
    my ($codex_link) = ($html =~ m#(http://codex.vlaanderen.be/ALLESNL/wet/zoek.vwp\?db=CODEX&numac=\d+)#smio);
    my ($numac) = ($codex_link =~ m/numac=(\d+)/);

    $init =~ s#(\d+)/(\d+)/(\d+)#$3-$2-$1#;
    $fini =~ s#(\d+)/(\d+)/(\d+)#$3-$2-$1#;
    $date =~ s#(\d+)/(\d+)/(\d+)#$3-$2-$1#;

    my $obj = {
        date => $date,
        title => $title,
        kind => $kind,
        numac => $numac,
        codex_link => $codex_link,
        timeframe => { starts => $init, ends => $fini },
        # body => $html,
        # plain => HTML::Strip->new()->parse($html),
    };


    # return unless defined $obj->{docuid};

    $dataType ||= 'perl';

    for ($dataType) {
        /html/i and return $html;
        /perl/i and return $obj;
        /json/i and return encode_json($obj);
    }

    return $html; # fallback html
}

sub request {
    my ($self, $docid, $format) = @_;

    my $drv = new BeLaws::Driver::LWP;
    my $req = $self->make_request(mbid => $docid);
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
