use strict;
use warnings;

use Module::Build;

my $build = Module::Build->new(
   module_name => 'Tickit::RenderContext',
   requires => {
      'Tickit::Pen' => '0.31', # as_immutable, equiv
      'Tickit::Utils' => '0.21', # string_count
      'perl' => '5.010', # switch
   },
   build_requires => {
      'Test::More' => '0.88', # done_testing
   },
   auto_configure_requires => 0, # Don't add M::B to configure_requires
   license => 'perl',
   create_makefile_pl => 'small',
   create_license => 1,
   create_readme  => 1,
);

$build->create_build_script;
