use strict;
use warnings;
use Test::More;
use Test::Deep;
use Data::Dumper;

BEGIN {
    use_ok('BeLaws::Query');
    use_ok('BeLaws::Driver::LWP');
}

use BeLaws::Query;
use BeLaws::Driver::LWP;

my $q = new BeLaws::Query();
my $req = $q->make_request(cn => "2010020901");

    isa_ok($req,'HTTP::Request');
    ok($req->{_method} eq "GET", "HTTP response from GET request");

my $res = BeLaws::Driver::LWP->new()->process($req);

    isa_ok($res, 'HTTP::Response');
    ok($res->decoded_content ne '', 'result must not be empty');

my $ret = $q->parse_response($res, 'json');

    ok($ret ne '', 'result must not be empty');

done_testing();
