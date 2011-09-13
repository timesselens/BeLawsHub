use strict;
use warnings;
use BeLaws::API;
use BeLaws::API::Staatsblad;
use BeLaws::Frontend;
use Data::Dumper;
use Plack::Builder;
use Plack::Middleware::Static;
use Plack::App::File;

my $error_logfile = $ENV{HOME}."/var/log/belawshub.error.log";

builder {
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
       enable "JSONP", callback_key => 'callback';
       mount "/search.json" => \&BeLaws::API::search;
       mount "/doc.json" => \&BeLaws::API::doc;
       mount "/status.json" => \&BeLaws::API::status;
       mount "/class" => builder {
           mount "/person.json" => \&BeLaws::API::class_person;
           mount "/cat.json" => \&BeLaws::API::class_cat;
           mount "/geo.json" => \&BeLaws::API::class_geo;
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
           mount "/fetch" => builder {
               mount "/staatsblad.json" => \&BeLaws::API::Staatsblad::fetch;
           };
           mount "/parse" => builder {
               mount "/staatsblad.json" => \&BeLaws::API::Staatsblad::parse;
           };
           mount "/format" => builder {
               mount "/staatsblad.json" => \&BeLaws::API::Staatsblad::format;
           };
           mount "/resolve" => builder {
               mount "/staatsblad.json" => \&BeLaws::API::Staatsblad::resolve;
           };
           mount "/info" => builder {
               mount "/staatsblad.json" => \&BeLaws::API::Staatsblad::info;
           };
           mount "/test" => builder {
               mount "/staatsblad.json" => \&BeLaws::API::Staatsblad::test;
           };
           mount "/stat" => builder {
               mount "/staatsblad.json" => \&BeLaws::API::Staatsblad::stat;
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
       return [ 302, [ 'Content-Type' => 'text/plain', 'Location' => '/app.html?q='.$q.'&d='.$d ], ['redirecting'] ];
   }; # }}}

   mount "/" => builder {
        enable 'Plack::Middleware::Static', path => qr{^/(images|js|vendor|html|css|favicon\.ico)}, root => 'html/';
        mount "/app.html" => Plack::App::File->new(file => 'html/app.html'); 
        mount "/doc.html" => \&BeLaws::Frontend::doc;
        mount "/" => builder {
            enable '+WebHive::Middleware::Template', dirs => ['./html/'];
            mount "/search.phtml" => \&BeLaws::Frontend::search;
            mount "/" => Plack::App::File->new(file => 'html/index.html'); #catchall
        };
   };

};

# vim: ft=perl
