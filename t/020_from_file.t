use strict;
use warnings;
use Test::More;
use Test::Deep;
use Data::Dumper;
use FindBin qw/$Bin/;

BEGIN {
    use_ok('BeLaws::Query');
}

use BeLaws::Query;

my $q = new BeLaws::Query();
my $ret = $q->parse_response($Bin.'/data/test.html', 'json');

    ok($ret ne '', 'result must not be empty');

print Dumper $ret;
done_testing();
