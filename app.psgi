use strict;
use warnings;
use BeLaws::API;
use BeLaws::API::Staatsblad;
use BeLaws::Frontend;
use Data::Dumper;
use Plack::Builder;
use Plack::Middleware::Static;
use Plack::App::File;
use WebHive::Router;
use Plack::Middleware::Throttle::Hourly;
use Plack::Middleware::Throttle::Backend::Hash;

my $error_logfile = $ENV{HOME}."/var/log/belawshub.error.log";

our $app = builder {
   for(0..$#ARGV) { 
       if($ARGV[$_] =~ /^--error-log$/) { 
           $error_logfile = $ARGV[$_+1] if defined $ARGV[$_+1];
           warn sprintf "errorlog has been redirected to %s", $error_logfile;
           open STDERR, ">>", $error_logfile or die $!;
           last;
       } 
   }
   enable "HTTPExceptions";
   mount "/api" => builder {
       # enable 'Debug::DBIProfile', profile => 2;
       enable "Throttle::Hourly", max => 1000, backend => Plack::Middleware::Throttle::Backend::Hash->new();
       enable "JSONP", callback_key => 'callback';
       mount "/search.json" => \&BeLaws::API::search;
       mount "/doc.json" => \&BeLaws::API::doc;
       mount "/status.json" => \&BeLaws::API::status;
       mount "/top.json" => \&BeLaws::API::Staatsblad::top;
       mount "/class" => builder {
           mount "/person.json" => \&BeLaws::API::class_person;
           mount "/cat.json" => \&BeLaws::API::class_cat;
           mount "/geo.json" => \&BeLaws::API::class_geo;
       };
       mount "/retry" => builder {
           mount "/staatsblad" => \&BeLaws::API::Staatsblad::retry;
       };
       mount "/info" => builder {
           mount "/staatsblad.json" => \&BeLaws::API::Staatsblad::format;
           mount "/raadvanstate.json" => \&BeLaws::API::info_raadvanstate;
           mount "/juridat.json" => \&BeLaws::API::info_juridat;
       };
       mount "/stats" => builder {
           mount "/person_party.json" => \&BeLaws::API::stats_person_party;
           mount "/person_cosign.json" => \&BeLaws::API::stats_person_cosign;
           mount "/word_trends_per_month.json" => \&BeLaws::API::word_trends_per_month;
       };
       mount "/seed" => builder {
           mount "/docuid.json" => \&BeLaws::API::Staatsblad::seed;
       };
       mount "/internal/" => builder {
           enable "Access", rules => [ allow => "127.0.0.0/8" ];
           mount "/" => sub { return [ 200, [ 'Content-Type' => 'text/plain' ], [ "usage:\n\t" . join "\n\t", map { "/api/internal/$_" } qw/fetch parse format resolve info test stat/] ] };
           mount "/fetch" => builder {
               mount "/" => sub { return [ 200, [ 'Content-Type' => 'text/plain' ], [ "usage:\n\t/api/internal/fetch/staatsblad.json?docuid=YYYY-MM-DD/NN" ] ] };
               mount "/staatsblad.json" => \&BeLaws::API::Staatsblad::fetch;
           };
           mount "/parse" => builder {
               mount "/" => sub { return [ 200, [ 'Content-Type' => 'text/plain' ], [ "usage:\n\t/api/internal/parse/staatsblad.json?docid=YYYY-MM-DD/NN" ] ] };
               mount "/staatsblad.json" => \&BeLaws::API::Staatsblad::parse;
           };
           mount "/format" => builder {
               mount "/" => sub { return [ 200, [ 'Content-Type' => 'text/plain' ], [ "usage:\n\t/api/internal/format/staatsblad.json?docid=YYYY-MM-DD/NN" ] ] };
               mount "/staatsblad.json" => \&BeLaws::API::Staatsblad::format;
           };
           mount "/resolve" => builder {
               mount "/" => sub { return [ 200, [ 'Content-Type' => 'text/plain' ], [ "usage:\n\t/api/internal/resolve/staatsblad.json?docuid=YYYY-MM-DD/NN" ] ] };
               mount "/staatsblad.json" => \&BeLaws::API::Staatsblad::resolve;
           };
           mount "/info" => builder {
               mount "/" => sub { return [ 200, [ 'Content-Type' => 'text/plain' ], [ "usage:\n\t/api/internal/info/staatsblad.json?docuid=YYYY-MM-DD/NN" ] ] };
               mount "/staatsblad.json" => \&BeLaws::API::Staatsblad::info;
           };
           mount "/test" => builder {
               mount "/" => sub { return [ 200, [ 'Content-Type' => 'text/plain' ], [ "usage:\n\t/api/internal/test/staatsblad.json?docuid=YYYY-MM-DD/NN" ] ] };
               mount "/staatsblad.json" => \&BeLaws::API::Staatsblad::test;
           };
           mount "/stat" => builder {
               mount "/" => sub { return [ 200, [ 'Content-Type' => 'text/plain' ], [ "usage:\n\t/api/internal/stat/staatsblad.json?docuid=YYYY-MM-DD/NN" ] ] };
               mount "/staatsblad.json" => \&BeLaws::API::Staatsblad::stat;
           };
           mount "/top" => builder {
               mount "/" => sub { return [ 200, [ 'Content-Type' => 'text/plain' ], [ "usage:\n\t/api/internal/stat/staatsblad.json?docuid=YYYY-MM-DD/NN" ] ] };
               mount "/staatsblad.json" => \&BeLaws::API::Staatsblad::top;
           };
       };
       mount "/list.json" => \&BeLaws::API::search; # backwards compat
   };


   mount "/developer" => builder {
        mount "/doc" => builder {
            mount "/api.v1.html" => Plack::App::File->new(file => 'html/developer/doc/api.v1.html');
        };
        mount "/test" => builder {
            mount "/" => Plack::App::File->new(file => 'html/developer/test/index.html');
        };
   };

   mount "/statistics" => builder {
       enable 'Plack::Middleware::Static', path => qr{^/\w+\.html}, root => 'html/statistics';
       mount "/" => Plack::App::File->new(file => 'html/statistics/index.html'); #catchall
   };

   # redirection of alpha API to beta {{{
   mount "/doc" => builder {
       mount "/show.html" => sub {
            my ($q,$d) = (shift->{REQUEST_URI} =~ m#&q=([^&]+)&d=([\d\-\/]+)#);
            return [ 302, [ 'Content-Type' => 'text/plain', 'Location' => '/doc.html?q='.$q.'&d='.$d ], ['redirecting'] ];
       }
   };
   mount "/d/" => sub {
       my ($d) = (shift->{REQUEST_URI} =~ m#/d/([\d\-\/]+)#);
       return [ 302, [ 'Content-Type' => 'text/plain', 'Location' => '/doc.html?d='.$d ], ['redirecting'] ];
   };
   mount "/s/" => sub {
       my ($q,$d) = (shift->{REQUEST_URI} =~ m#/s/([^/]+)/d/([\d\-\/]+)#);
       return [ 302, [ 'Content-Type' => 'text/plain', 'Location' => '/app.html?q='.$q.'&d='.$d ], ['redirecting'] ] };

   # redirection of old html files
   mount "/index.html" => sub { return [ 302, [ 'Content-Type' => 'text/plain', 'Location' => '/index.phtml' ], ['redirecting'] ] };
   mount "/search.html" => sub { return [ 302, [ 'Content-Type' => 'text/plain', 'Location' => '/index.phtml' ], ['redirecting'] ] };
   # }}}

   mount "/" => builder {
        enable 'Plack::Middleware::Static', path => qr{^/(images|js|vendor|html|css|favicon\.ico|app\.html|index\.html|app)}, root => 'html/';
        enable '+WebHive::Middleware::Template', dirs => ['./html/'];
        
        router {
            namespace 'BeLaws';
            get '/{lang}/{year}/{no}' => { controller => 'Frontend', action => 'saved_doc' },
            get '/{lang}/{year}/{no}/' => { controller => 'Frontend', action => 'saved_doc' },
            get '/doc.html' => { controller => 'Frontend', action => 'doc' },
            get "/" => { controller => 'Frontend', action => 'index' },
            get "/index.phtml" => { controller => 'Frontend', action => 'index' },
            get "/search.phtml" => { controller => 'Frontend', action => 'search' },
            #get "/" => Plack::App::File->new(file => 'html/index.html'); #catchall
        };
   };

};

# vim: ft=perl
