package WebHive::Middleware::Template;
use common::sense;
use parent qw/Plack::Middleware/;
use Plack::Request;
use Plack::Util;
use WebHive::Log qw/warn info/;
use Template::Mustache;
use Plack::Util::Accessor qw/dirs/; 
use File::Slurp qw/slurp/;
use Encode;

# ABSTRACT: Mustache Templates for WebHive
# COPYRIGHT: Tim Esselens 2011 <tim.esselens@gmail.com>

sub prepare_app {
    my ($self) = shift;
}

sub call {
    my ($self, $env) = @_;
    my $nav_file;

    my $res = $self->app->($env);


    my $path = $env->{PATH_INFO};

    # append '/' when no extention is found in requested url ie: /foo/baz
    if($path !~ m/\.\w+$/ && $path !~ m/\/$/) { $path .= '/' }

    # append 'index.phtml' when path ends in '/'
    if($path =~ m/\/$/) { $path .= 'index.phtml' }

    warn "not performing templating on '$path' without .phtml extention or \$env{webhive.template.force}=1" 
        and return $self->response_cb($res, sub { return shift }) 
            unless ($env->{'webhive.template.force'} || $path =~ m/\.phtml$/);

    # extract dir and filename from the $path
    my ($uridir,$template) = ($path =~ m/^([\w\d\-\_\/\.]*)\/([^\/]+\.\w+)$/ );

    # allows setting template filename, see Router.pm
    if ($env->{'webhive.template.fn'}) {
        $template = $env->{'webhive.template.fn'};
    }

    # create a list of paths either from 'dirs' or the +Config document_roots
    my @path = grep { defined } ($ENV{DOCUMENT_ROOT}, @{$self->dirs || []}, map { $_->{document_root} } (@$env{'webhive.vhost_config', 'webhive.server_config'}));
    my ($templ_file) = grep { -f } map { s/\.+/./g; s#/\.?/#/#g; $_ } 
                        ( (map { $_ .'/'.$uridir . '/'. $template } @path),
                          (map { $_ .'/'. $template } @path )
                        );

    if($templ_file) {
            # info(">>> got template '%s'",$templ_file);
            $res->[1] ||= [ 'Content-Type' => 'text/html; charset=utf-8' ];
            $res->[2] ||= [ slurp($templ_file) ];
    } else {
        warn "no template '%s' found in %o env=%o", $template, \@path, $env;
    }


    $self->response_cb($res, sub {
        my $res = shift;
        if(exists $env->{'templhash'}) { # && Plack::Util::header_get($res->[1], 'Content-Type') =~ m#text/html#) {
            # will cause mustache to render html commented style tags
            # warn "URI %o CONT %o",$env,$res->[1];
            my $use_html_tags = "{{=<!--{ }-->=}}";
            Plack::Util::header_remove($res->[1], 'Content-Length'); 
            my @body ;

            if($res->[2]) {
                if(ref $res->[2] eq 'ARRAY') { @body = @{$res->[2]}; }
                elsif($res->[2]->can('getline')) { while(defined(my $line = $res->[2]->getline())) { push @body,$line } }
            }

            my $template = new Template::Mustache::Template( decode('utf-8',$use_html_tags . join("",@body)));
            my $context  = new Template::Mustache::Context($env->{'templhash'});
            $res->[2] = [ encode('utf-8',$template->render($context)) ];
        } 

        # warn "returning %o",$res;

        return $res;
    });
}

sub uri_to_file {
    my $uri = shift;

    return unless $uri =~ m/(|\.phtml)$/;
    
    if($uri =~ m/\/$/) { $uri .= "index.phtml" }

    $uri =~ s/\.\.//g;

    return "./html/$uri";
}

42;
