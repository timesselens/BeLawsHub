package BeLaws::Query::juridat;
use strict;
use warnings;
use Carp qw/croak/;
use HTTP::Request::Common;
use HTTP::Response;
use BeLaws::Driver::LWP;
use JSON::XS;
use MIME::Base64;
use Data::Dumper;
use HTML::Strip;
use XML::Simple;
use Encode;
use File::Slurp qw/slurp/;

###############################################################################
# Author: Tim Esselens <tim.esselens@gmail.com> (c) 2011 iRail vzw/asbl [AGPL]
###############################################################################

sub new {
    my $class = shift;
    my $self = {};
    $self->{base} = "http://jure.juridat.just.fgov.be";
    $self->{url}  = "/PRDJURSEARCH/JuridatSearchSoapHttpPort";
    $self->{params} = { };
    return bless ($self, $class);
}

sub make_request {
    my $self = shift;
    my %attr = ref $_[0] eq 'HASH' ? %{$_[0]} : @_; # so both `f({a=>1})` and `f(a=>1)` are allowed

    croak 'id is a required argument' unless defined $attr{id};
    croak 'id is malformed' unless $attr{id} =~ m/^\d+$/;

    my $url = $self->{base} .  $self->{url};
    my $id = $attr{id};

    my $xmlreq = <<"EOF";
<SOAP-ENV:Envelope xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
    <SOAP-ENV:Body SOAP-ENV:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
        <tns:getIndexCard xmlns:tns="http://search.juridat.bull.be/">
            <indexCardId xsi:type="xsd:long">$id</indexCardId>
            <showMarkup xsi:type="xsd:boolean">true</showMarkup> 
            <markup xsi:type="xsd:string"></markup> 
        </tns:getIndexCard> 
    </SOAP-ENV:Body> 
</SOAP-ENV:Envelope>
EOF

    my $req = POST $url, Content_Type => 'text/xml; charset=utf-8', Content => $xmlreq;

    return $req;

}

sub parse_response {
    my ($self, $in, $dataType) = @_;

    my $html = ref $in eq 'HTTP::Response' ? $in->decoded_content() : 
                -e $in ? slurp($in) :
                $in;


   my $obj = XMLin($html,
        NoAttr => 1,
        SuppressEmpty => '',
        NormaliseSpace => 2,
        ForceArray => [ 'ns0:ArrayOfArticle', 'ns0:Publication' ],
        KeepRoot => 0,
        KeyAttr => [],
    );

    if(defined $obj->{'env:Body'}) { $obj = $obj->{'env:Body'} }

    my $normalize;
       $normalize = sub {
        my $obj = shift;
        foreach my $key (keys %$obj) {
            my $name = lc $key;
               $name =~ s/(ns0:|idxc_|dec_)//g;
            $obj->{$name} = $obj->{$key};
            delete $obj->{$key};

            if(ref $obj->{$name} eq "HASH") { $normalize->($obj->{$name}); }
            if(ref $obj->{$name} eq "ARRAY") { $normalize->($_) foreach @{$obj->{$name}} }
        }
    };

    $normalize->($obj);

    foreach ($obj->{indexcard}->{summary}, 
             $obj->{indexcard}->{hide}, 
             $obj->{indexcard}->{note}, 
             $obj->{indexcard}->{freekeyword} ) { $_ = decode('utf8',decode_base64($_)) }

    #my $obj = {
    #    id => $id,
    #    date => $date,
    #    title => $title,
    #    body => $html,
    #    plain => HTML::Strip->new()->parse($html),
    #};

    my ($justel,$lang) = @{$obj->{indexcard}}{qw/decjustel declangue/};

    my $xmltxtreq = <<"EOF";
<SOAP-ENV:Envelope xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">                                                                                                                                                                          
<SOAP-ENV:Body SOAP-ENV:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
    <tns:getDecision xmlns:tns="http://search.juridat.bull.be/"> 
        <did xsi:type="tns:DecisionIdentifier"> 
            <tns:justel xsi:type="xsd:string">$justel</tns:justel> 
            <tns:langue xsi:type="xsd:string">$lang</tns:langue> 
            <tns:markup xsi:type="xsd:string"></tns:markup> 
            <tns:showMarkup xsi:type="xsd:boolean">true</tns:showMarkup> 
        </did> 
    </tns:getDecision>
</SOAP-ENV:Body> 
</SOAP-ENV:Envelope> 
EOF

    warn $xmltxtreq; 
    my $drv = new BeLaws::Driver::LWP;
    my $res = $drv->process(POST 'http://jure.juridat.just.fgov.be/PRDJURSEARCH/JuridatSearchSoapHttpPort',
                            Content_Type => 'text/xml; charset=utf-8',
                            Content => $xmltxtreq);

    my $textobj = XMLin($res->decoded_content(),
        NoAttr => 1,
        SuppressEmpty => '',
        NormaliseSpace => 2,
        ForceArray => [ 'ns0:ArrayOfArticle', 'ns0:Publication' ],
        KeepRoot => 0,
        KeyAttr => []);

    if(defined $textobj->{'env:Body'}) { $textobj = $textobj->{'env:Body'} }

    $normalize->($textobj);

    foreach ($textobj->{decision}->{text}) { $_ = decode('utf8',decode_base64($_)) }

    $obj->{text} = $textobj;


    $dataType ||= 'perl';

    for ($dataType) {
        /xml/i and return $html;
        /html/i and return $html;
        /perl/i and return $obj;
        /json/i and return encode_json($obj);
    }

    return $html; # fallback html
}


sub request {
    my ($self, $docid, $format) = @_;

    my $drv = new BeLaws::Driver::LWP;
    my $req = $self->make_request(id => $docid);
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
