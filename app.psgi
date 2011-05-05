use strict;
use warnings;
use BeLaws::API;
use BeLaws::Frontend;
use Data::Dumper;
use Plack::Builder;
use Plack::Middleware::Static;
use Plack::App::File;


builder {
   mount "/api/" => builder {
       mount "/list.json" => $BeLaws::API::list;
       mount "/doc.json" => $BeLaws::API::doc;
   };

   mount "/doc/" => builder {
       mount "/show.html" => $BeLaws::Frontend::doc;
   };

   mount "/" => builder {
        enable 'Plack::Middleware::Static', path => qr{^/(images|js|vendor|html|css|favicon\.ico)}, root => 'html/';
        mount "/" => Plack::App::File->new(file => 'html/index.html');
        mount "/index.html" => Plack::App::File->new(file => 'html/index.html');
        mount "/intro.html" => Plack::App::File->new(file => 'html/intro.html');
   };

};

# vim: ft=perl
