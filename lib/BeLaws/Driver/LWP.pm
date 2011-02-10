package BeLaws::Driver::LWP;
use parent 'Exporter';
use strict;
use Carp qw/croak/;
use LWP::UserAgent;

our $VERSION;

sub new {
    my ($proto) = @_;
    my $class = ref $proto || $proto;
    my %attr = ( _client => new LWP::UserAgent);
        
    $attr{_client}->timeout(10);
    $attr{_client}->agent( ($ENV{BELAWS_UA} || "BeLaws::Driver::LWP/$VERSION ") );
                                       
    return bless {%attr}, $class;
}

sub process {
    my $self = shift;
    my $http_req = shift;

    my $response = $self->{_client}->request($http_req);
    $response->is_success or croak 'unable to process request: '.$response->status_line;

    return $response;
}

42;
