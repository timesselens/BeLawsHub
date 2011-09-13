package WebHive::Router;
use parent 'Exporter';
use WebHive::Log qw/warn notice/;
use Router::Simple;
use Plack::App::File;
our @EXPORT = qw/router get put post namespace falltrough/;

# ABSTRACT: Router Simple syntax sugar
# COPYRIGHT: Tim Esselens 2011 <tim.esselens@gmail.com>

our $_ROUTERS = {};
our $nss = {};
our $falltroughs = {};

sub router(&) {
    my $sub = $_[0];
    my $from = join '_',(caller(0))[1,2];
    $_ROUTERS{$from} = new Router::Simple;
    $sub->();
    notice "setup routes: \n%s",$_ROUTERS{$from}->as_string;
    return sub {
        my $env = shift;
        if(my $route = $_ROUTERS{$from}->match($env)) {
             my $mod = join( '::', grep { defined $_ } ($nss{$from} , $route->{controller}));
             eval "require $mod"; if($@) { die ($@) };
             $env->{route} = $route;
             $env->{'webhive.template.fn'} = $route->{template};
             #notice('routing to module %o with sub %o', $mod, $route->{action});
             if($mod->can('PH_'.$route->{action})) {
                 my $sub = $mod.'::PH_'.$route->{action};
                 return $sub->($env);
             } elsif($mod->can('AJAX_'.$route->{action})) {
                 my $sub = $mod.'::AJAX_'.$route->{action};
                 return $sub->($env);
             } elsif($mod->can($route->{action})) {
                 my $sub = $mod.'::'.$route->{action};
                 return $sub->($env);
             } else {
                 return [ 404, [ 'Content-Type' => 'text/plain' ], [ 'route not found' ] ]
             }
        } else {
            if(-d $falltroughs{$from}) {
                notice 'using fallthrough [%s] with PATH_INFO = %s',$falltroughs{$from},$env->{PATH_INFO};
                return Plack::App::File->new({ root => $falltroughs{$from} })->to_app->($env);
            } else {
                return [ 404, [ 'Content-Type' => 'text/plain' ], [ 'not found by router' ] ];
            }
        }
    }
}


sub get {
    my ($pattern,$hash) = @_;
    my $from = join '_',(caller(2))[1,2];
    my $name = $hash->{controller} . "::" . $hash->{action};
    $_ROUTERS{$from}->connect($name,$pattern, $hash, { method => "GET" });
}

sub put {
    my ($pattern,$hash) = @_;
    my $from = join '_',(caller(2))[1,2];
    my $name = $hash->{controller} . "::" . $hash->{action};
    $_ROUTERS{$from}->connect($name,$pattern, $hash,{ method => "PUT"});
}

sub post {
    my ($pattern,$hash) = @_;
    my $from = join '_',(caller(2))[1,2];
    my $name = $hash->{controller} . "::" . $hash->{action};
    $_ROUTERS{$from}->connect($name,$pattern, $hash,{ method => "POST"});
}

sub namespace { 
    my $from = join '_',(caller(2))[1,2];
    $nss{$from} = shift;
    warn "%o %o",$from,$nss{$from};
}

sub falltrough { 
    my $from = join '_',(caller(2))[1,2];
    $falltroughs{$from} = shift ;
}

42;

