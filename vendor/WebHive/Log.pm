package WebHive::Log;
use strict;
use warnings;
use Digest::SHA1 qw/sha1_hex/;
use Data::Dumper;

BEGIN {
    use Exporter   ();
    our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);

    $VERSION     = 1.00;
    @ISA         = qw(Exporter);
    @EXPORT      = map { "&$_" } qw/warn info/;
    @EXPORT_OK   = map { "&$_" } qw/emerg alert crit error warn notice info debug munge_arguments/;

    if($ENV{MOD_PERL}) {
        use Apache2::RequestUtil;
        use Apache2::Const map { "LOG_$_" } qw/EMERG ALERT CRIT ERR WARNING NOTICE INFO DEBUG STARTUP/;
        use APR::Const qw/SUCCESS/;
    }
}

sub mod_perl { $ENV{MOD_PERL} }
sub stderr { print STDERR (shift)."\n"; }
sub serverlog {
    my ($lvl, $msg) = @_;
    my $r = Apache2::RequestUtil->request;
    my $s = $r->server;
    my ($package, $filename, $line) = caller(1);
    $msg ||= 'ERROR';

    if($r->dir_config("do_not_warn_on_head_req") && $r->method eq "HEAD") { return }
    # binary OR with LOG_STARTUP will remove timestamps from warnings
    $s->log_serror($filename, $line, $lvl | LOG_STARTUP, SUCCESS, $msg);
}


# logging subroutines ################################################################################
sub emerg {
    my $msg = munge_arguments('[%P] %s',munge_arguments(@_));
    mod_perl() ? serverlog(LOG_EMERG,$msg) : stderr($msg);
}
sub alert {
    my $msg = munge_arguments('[%P] %s',munge_arguments(@_));
    mod_perl() ? serverlog(LOG_ALERT,$msg) : stderr($msg);
}
sub crit {
    my $msg = munge_arguments('[%P] %s',munge_arguments(@_));
    mod_perl() ? serverlog(LOG_CRIT,$msg) : stderr($msg);
}
sub error {
    my $msg = munge_arguments('[%P] %s',munge_arguments(@_));
    mod_perl() ? serverlog(LOG_ERR,$msg) : stderr($msg);
}
sub warn {
    my $msg = munge_arguments('[%P] %s',munge_arguments(@_));
    mod_perl() ? serverlog(LOG_WARNING,$msg) : stderr($msg);
}
sub notice {
    my $msg = munge_arguments('[%P] %s',munge_arguments(@_));
    mod_perl() ? serverlog(LOG_NOTICE,$msg) : stderr($msg);
}
sub info {
    my $msg = munge_arguments('[%P] %s', munge_arguments(@_));
    mod_perl() ? serverlog(LOG_INFO,$msg) : stderr($msg);
}
sub debug {
    my $msg = munge_arguments('[%P] %s',munge_arguments(@_));
    mod_perl() ? serverlog(LOG_DEBUG,$msg) : stderr($msg);
}

# a common method for all functions, munges (string, ... ) to a string sprintf wise #####################
sub munge_arguments {
    my @args = @_;
    my $msg = shift @args;
    my $ret;
    my ($package, $filename, $line) = caller(1);
    my ($basename) = (($filename || '') =~ m/([^\/]+)$/);
    if($msg and ! $args[0]) {
        $ret = $msg;
        $ret =~ s/\%P/$package/;
        $ret =~ s/\%F/$basename/;
        $ret =~ s/\%L/$line/;
        $ret = sprintf($ret);
    } else {
        my @results = @args;
        (my @sstrings) = ($msg =~ m/(\%\w)/g);
        for(my $i = 0; $i <= $#sstrings; $i++) {
            if($sstrings[$i] =~ m/\%o/) {
                my $a = $args[$i];
                $results[$i] = Dumper($a);
                $results[$i] =~ s/\$VAR1\ =\ //gio;
                $results[$i] =~ s/;\s*$//gio;
            }
            elsif($sstrings[$i] =~ m/\%S/) {
                my $a = $args[$i];
                $results[$i] = substr(sha1_hex(map { s/\$VAR1\ =\ //io; s/;\s*$//o; $_; } Dumper($a)),0,6);
            } 
        }
        $msg =~ s/\%[oS]/\%s/g;
        $msg =~ s/\%P/$package/;
        $msg =~ s/\%F/$basename/;
        $msg =~ s/\%L/$line/;
        $ret = sprintf($msg,@results);
    }
    
    return $ret;
}   




42;
