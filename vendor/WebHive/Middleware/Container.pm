package WebHive::Middleware::Container;
use strict;
use warnings;
use parent qw/Plack::Middleware/;
use Plack::Request;
use Plack::Util::Accessor qw/dirs/; 
use WebHive::Log qw/warn/;
use File::Slurp qw/slurp/;

my $cache = {};
my $template = "nav.phtml";

# ABSTRACT: Container wrapper middleware for PSGI apps
# COPYRIGHT: Tim Esselens 2011 <tim.esselens@gmail.com>

sub prepare_app {
    my ($self) = shift;
}

sub call {
    my ($self, $env) = @_;
    my ($pre, $post);

    die 'the dirs argument must be an array ref' unless ref ($self->dirs || []) eq 'ARRAY';

    my @path = grep { defined } ($ENV{DOCUMENT_ROOT}, @{$self->dirs || []}, map { $_->{document_root} } @$env{'webhive.vhost_config', 'webhive.server_config'});
    my ($nav_file) = grep { -f } map { $_ .'/'.$template } @path;

    $env->{'webhive.container.path'} = \@path;
    $env->{'webhive.container.file'} = $nav_file;

    my $res = $self->app->($env);
    return $res if exists $env->{no_nav};
    return $res unless ref $res eq 'ARRAY';
    return $res unless(Plack::Util::header_get($res->[1], 'Content-Type') =~ m#text/html#);

    $nav_file && -f $nav_file 
        or warn 'nav file %s not found in %o',$template, \@path
        and return [ '403', [ 'Content-Type' => 'text/plain' ], [ 'no nav found' ] ];

    $env->{'webhive.container.seen'} ||= {};
    $env->{'webhive.container'} = $nav_file;

    if(exists $cache->{$nav_file}) {
        ($pre,$post) = ($cache->{$nav_file}->{pre}, $cache->{$nav_file}->{post});
    } else {
        my $nav_cont = slurp($nav_file) or warn $!;
        ($pre,$post) = ($cache->{$nav_file}->{pre}, $cache->{$nav_file}->{post}) 
                     = split /(?:<!--{|{{)include[_\-]?template(?:}}|}-->)/io, $nav_cont, 2;
    }

    return $self->response_cb($res, sub {
        my $res = shift;
        my $cont = $env->{'webhive.container'};
        my $seen = $env->{'webhive.container.seen'};

        return $res if $env->{'webhive.nocontainer'};

        defined $seen->{$cont} and warn "tried wrapping twice" and return $res;
        
        $seen->{$cont} = 1;

        Plack::Util::header_remove($res->[1], 'Content-Length'); 

        if (defined $res->[2]) {
            if (ref $res->[2] eq 'ARRAY') {
                $res->[2] = [ $pre, @{$res->[2]}, $post ];
            } else {
                my @body;
                while(defined(my $line = $res->[2]->getline())) { push @body, $line; }
                $res->[2] = [ $pre, @body, $post];
            }   
        }

        # warn "returning res %o",$res;

        return $res;

    });
}

42;
