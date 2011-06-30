#!/usr/bin/perl
use strict;
use warnings;
use SOAP::WSDL;
use SOAP::Lite;
use LWP::UserAgent;
use HTTP::Request::Common;
use Data::Dumper;
use MIME::Base64;

# my $soap = SOAP::Lite->service('file:///tmp/JuridatSearchSoapHttpPort.wsdl' );
# my $result = $soap->call('JuridatSearch_getDecision', 'F-19970306-3');


my $ua = new LWP::UserAgent();
   $ua->agent('Mozilla/4.0 (compatible; MSIE 7.0; Windows NT 6.0)');

my $xmlreq = <<EOF;
<SOAP-ENV:Envelope xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"> 

<SOAP-ENV:Body SOAP-ENV:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
    <tns:getDecision xmlns:tns="http://search.juridat.bull.be/"> 
        <did xsi:type="tns:DecisionIdentifier"> 
            <tns:justel xsi:type="xsd:string">N-19701125-1</tns:justel> 
            <tns:langue xsi:type="xsd:string">NL</tns:langue> 
            <tns:markup xsi:type="xsd:string"></tns:markup> 
            <tns:showMarkup xsi:type="xsd:boolean">true</tns:showMarkup> 
        </did> 
    </tns:getDecision>
</SOAP-ENV:Body> 
</SOAP-ENV:Envelope> 
EOF

my $xmlreq2 = <<EOF;
<SOAP-ENV:Envelope xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"> 
<SOAP-ENV:Body SOAP-ENV:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"> 
    <tns:getIndexCard xmlns:tns="http://search.juridat.bull.be/"> 
        <indexCardId xsi:type="xsd:long">128514</indexCardId> 
        <showMarkup xsi:type="xsd:boolean">true</showMarkup> 
        <markup xsi:type="xsd:string"></markup> 
    </tns:getIndexCard> 
</SOAP-ENV:Body> 
</SOAP-ENV:Envelope>
EOF

my $r = $ua->request(POST 'http://jure.juridat.just.fgov.be/PRDJURSEARCH/JuridatSearchSoapHttpPort', 
                    Content_Type => 'text/xml; charset=utf-8', 
                    Content => $xmlreq2);
my $c = $r->content();

    my (@base64) = ($c =~ m/:base64Binary">([^<]+)</g);

    print decode_base64($_) ."\n\n" foreach @base64;

print Dumper $r;
