package BeLaws::Query::ejustice_fgov::kind;
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
    my $self = {};
    $self->{base} = 'http://www.ejustice.just.fgov.be';
    $self->{url} = '/cgi_wet/loi_rech.pl';
    $self->{params} = {
        language	=> 'nl',
		cc	=>'',
		choix1	=>'EN',
		choix2	=>'EN',
		cn_d_ecran	=>'04',
		cn_m_ecran	=>'04',
		cn_num_ecran	=>39,
		cn_y_ecran	=>2001,
		ddda	=>'',
		dddj	=>'',
		dddm	=>'',
		ddfa	=>'',
		ddfj	=>'',
		ddfm	=>'',
		dt	=> '',
		dtnum	=>'',
		nl	=>'n',
		nm_ecran	=>'',
		pdda	=>'',
		pddj	=>'',
		pddm	=>'',
		pdfa	=>'',
		pdfj	=>'',
		pdfm	=>'',
		'rech.x'	=>0,
		'rech.y'	=>0,
		so	=>'',
		text1	=>'',
		text2	=>'',
		text3	=>'',
		trier	=>'afkondiging',
    };
    return bless ($self, $class);

}

sub make_request {
    my $self = shift;
    my %attr = ref $_[0] eq 'HASH' ? %{$_[0]} : @_; # so both `f({a=>1})` and `f(a=>1)` are allowed

    croak 'cn is a required argument' unless defined $attr{cn};
    $attr{cn} =~ s/\W//gio; # convert 2010-13-03/23 into 2010031323
    croak 'cn is malformed' unless $attr{cn} =~ m/^[0-9a-z]+$/i;

    my ($y,$m,$d,$num) = ($attr{cn} =~ m/^(\d{4})(\d{2})(\d{2})([0-9a-z]{2})/);

    croak 'dt is a required argument' unless defined $attr{dt};
    croak 'dt is malformed' unless $attr{dt} =~ m/^[0-9a-z\ \(\)\-\,]+$/i;

    @{$self->{params}}{qw/dt cn_y_ecran cn_m_ecran cn_d_ecrean cn_num_ecran/} = (uc $attr{dt},$y,$m,$d,$num);
    # @{$self->{params}}{qw/dt/} = (uc $attr{dt});
    # the order of these params is important! *sigh* just lost 3 hours; 
    my @params = (qw/language cc choix1 choix2 cn_d_ecran cn_m_ecran cn_num_ecran cn_y_ecran ddda dddj dddm ddfa ddfj ddfm dt dtnum nl nm_ecran pdda pddj pddm pdfa pdfj pdfm rech.x rech.y so text1 text2 text3 trier/);

    my $url = $self->{base} .
              $self->{url} . 
              '?'. join '&', (map { $_.'='.$self->{params}->{$_} } @params);
        
    # warn "requesting ".$attr{dt}." $y $m $d $url ";
    my $req = new HTTP::Request(GET => $url);

    return $req;

}

sub parse_response {
    my ($self, $in, $dataType) = @_;
    $dataType ||= 'perl';

    my $html = ref $in eq 'HTTP::Response' ? encode('utf-8',$in->decoded_content()) : $in;    

    my $aantal = "x";
    ($aantal) = ($html =~ m/color=#FF8C00\>\s*(\d+)\s*<\/font>/);
    my $obj = {
        count => $aantal,
    };

    # warn Dumper($obj);

    for ($dataType) {
        /html/i and return $html;
        /perl/i and return { map { $_ => $obj->{$_} } keys %$obj };
        /sql_row/i and return { map { $_ => $obj->{$_} } (qw/kind/) };
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

BeLaws::Query::ejustice_fgov::kind - A HTTP request/resonse interface for www.ejustice.just.fgov.be (working title)

=head1 SYNOPSIS

use BeLaws::Query::ejustice_fgov::kind;

my $beq = new BeLaws::Query::ejustice_fgov::kind();
my $response = $beq->request('2010020901','html');

print $response;

=head1 AUTHORS

Tim Esselens <tim.esselens@gmail.com>
