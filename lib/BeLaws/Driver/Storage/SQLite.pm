package BeLaws::Driver::Storage::SQLite;
use DBI;
use common::sense;
use Carp qw/croak/;
use base 'BeLaws::Driver::Storage';

sub new {
    my ($proto, $attr) = @_;
    my $class = ref $proto || $proto;
    my %attr = ( table => 'belaws_docs', 
                 dir => './db', 
                 file => 'belaws.sqlite', %{$attr || {}});

    -d $attr{dir} or
        mkdir $attr{dir} or
            die 'unable to create '.$attr{dir};

    my $dbh = $attr{dbh} = DBI->connect("dbi:SQLite:dbname=".$attr{dir}.'/'.$attr{file},"","");

    my $count = $dbh->selectcol_arrayref('SELECT name FROM sqlite_master WHERE name = ?',undef,$attr{table});
    if(scalar @$count == 0) {
        warn "creating table...";
        $dbh->do('create virtual table '.$attr{table}.' USING fts4(title text, docuid text, pubid text, pubdate text, effective text, source text, body text, plain text, pages integer, pdf_href text)');
        $dbh->commit();
    }
    return bless {%attr}, $class;
}

sub fetch {
    my ($self, $id) = @_;
}

sub store {
    my ($self, $id) = @_;
}

42;
