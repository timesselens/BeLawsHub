package BeLaws::Driver::Storage::PostgreSQL;
use DBIx::Connector;
use common::sense;
use Carp qw/croak/;
use base 'Exporter';
use base 'BeLaws::Driver::Storage';

my $config; if(-e './config.pl') { eval { $config = do "./config.pl" }; if($@) { die $@."\n".$! } } 
our $db = BeLaws::Driver::Storage::PostgreSQL->new( { user => $config->{dbi_user} || $ENV{PGUSER}, host => $config->{dbi_host} || $ENV{PGHOST}, port => $config->{dbi_port} || $ENV{PGPORT} || 5432 } );
our @EXPORT = qw/$db/;

sub new {
    my ($proto, $attr) = @_;
    my $class = ref $proto || $proto;
    my %attr = ( db => 'belaws', %{$attr || {}});

    my $conn = $attr{conn} = DBIx::Connector->new("dbi:Pg:host=".($attr{host} || 'localhost').";port=".($attr{port} || 5432).";dbname=".$attr{db}, 
                                        $attr{user},
                                        $attr{pass},
                                        { RaiseError => 1, PrintError => 1, pg_enable_utf8 => 1 } );
    return bless {%attr}, $class;
}

sub get_dbh {
    return shift->{conn}->dbh;
}

sub fetch {
    my ($self, $id) = @_;
}

sub store {
    my ($self, $id) = @_;
}

42;
