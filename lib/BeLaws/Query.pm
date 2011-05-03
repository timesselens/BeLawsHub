package BeLaws::Query;
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
    $self->{base} = "http://www.ejustice.just.fgov.be";
    $self->{url}  = "/cgi_loi/loi_a1.pl";
    $self->{params} = {
        caller      => 'list',
        la          => 'N',
        sql         => "dt+not+contains+'foo'",
        language    => 'nl',
        chercher    => 't',
        fromtab     => 'wet_all'
    };
    return bless ($self, $class);
}

sub make_request {
    my $self = shift;
    my %attr = ref $_[0] eq 'HASH' ? %{$_[0]} : @_; # so both `f({a=>1})` and `f(a=>1)` are allowed

    croak 'cn is a required argument' unless defined $attr{cn};

    my $url = $self->{base} .
              $self->{url} . 
              '?' . join '&', ( 'cn='.$attr{cn}, (map { $_.'='.$self->{params}->{$_} } keys %{$self->{params}}));

    my $req = new HTTP::Request(GET => $url);

    return $req;

}

sub parse_response {
    my ($self, $in, $dataType) = @_;

    my $html = ref $in eq 'HTTP::Response' ? $in->decoded_content() : 
                -e $in ? slurp($in) :
                $in;

    my ($date,$title) = ($html =~ m#<th align\s*=\s*left\s*width=100%>\n</b><b>\s*([^\-]+)\s*\.\s*\-\s*([^<]+)\s*#smi);
    my ($bron) = ($html =~ m#<font color=Red>\s*<b>\s*Bron\s*:\s*</b></b>\s*</font>\s*([^<]+)\s*#smi);
    my ($pub) = ($html =~ m#<font color=Red>\s*<b>\s*Publicatie\s*:\s*</b>\s*</font>\s*([\d\-]+)\s*#smi);
    my ($num) = ($html =~ m#<font color=red>\s*nummer\s*:\s*</font>\s*([^<]+)\s*#smi);
    my ($blz) = ($html =~ m#<font color=red>\s*bladzijde\s*:\s*</font>\s*(\d+)\s*#smi);
    my ($pdf_href) = ($html =~ m#<a href=([^\s]+) target=_parent>BEELD</a>#smi);
    my ($dossiernr) = ($html =~ m#<font color=Red>\s*<b>\s*Dossiernummer\s*:\s*</b>\s*</font>\s*([^<]+)\s*#smi);
    my ($inwerking) = ($html =~ m#<font color=Red>\s*<b>\s*Inwerkingtreding\s*:\s*</b>\s*</font>\s*([\w\-]+)\s*#smi);

    my $obj = {
        date => $date,
        title => $title,
        source => $bron,
        pubdate => $pub,
        pubid => $num,
        docuid => $dossiernr,
        pages => $blz,
        pdf_href => $pdf_href,
        effective => $inwerking,
        body => $html,
        plain => HTML::Strip->new()->parse($html),
    };


    return unless defined $obj->{docuid};

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
