package BeLaws::Driver::Storage;
use common::sense;
use Carp qw/croak/;

sub new {
    my ($proto, $attr) = @_;
    my $class = ref $proto || $proto;
    my %attr = ( name => undef, %{$attr || {}});

    return bless {%attr}, $class;
}

sub fetch {
    my ($self, $id) = @_;
}

sub store {
    my ($self, $id) = @_;
}

sub get_dbh { return shift->{dbh} }

42;
