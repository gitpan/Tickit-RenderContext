#!/usr/bin/perl

use strict;
use warnings;

use Test::More;
use t::TestWindow qw( $win @methods );

use Tickit::RenderContext;

use Tickit::Pen;

my $rc = Tickit::RenderContext->new(
   lines => 10,
   cols  => 20,
);

# erase_at
{
   $rc->erase_at( 0, 0, 20, Tickit::Pen->new( fg => 5 ) );
   $rc->erase_at( 0, 5, 10, Tickit::Pen->new( fg => 5, b => 1 ) );

   $rc->render_to_window( $win );
   is_deeply( \@methods,
              [
                 [ goto => 0, 0 ],
                 [ erasech =>  5, 1,     { fg => 5         } ],
                 [ erasech => 10, 1,     { fg => 5, b => 1 } ],
                 [ erasech =>  5, undef, { fg => 5         } ],
              ],
              'RC renders erase' );
   undef @methods;
}

# erase VC explicit pen
{
   $rc->goto( 2, 6 );
   $rc->erase( 12, Tickit::Pen->new( u => 1 ) );
   $rc->goto( 3, 12 );
   $rc->erase_to( 16, Tickit::Pen->new( i => 1 ) );

   $rc->render_to_window( $win );
   is_deeply( \@methods,
              [
                 [ goto => 2, 6 ],
                 [ erasech => 12, undef, { u => 1 } ],
                 [ goto => 3, 12 ],
                 [ erasech => 4, undef, { i => 1 } ],
              ],
              'RC erase with virtual-cursor' );
   undef @methods;
}

# erase VC setpen
{
   $rc->goto( 4, 0 );
   $rc->setpen( Tickit::Pen->new( bg => 2 ) );
   $rc->erase( 5 );
   $rc->setpen( Tickit::Pen->new( bg => 3 ) );
   $rc->erase( 5 );

   $rc->render_to_window( $win );
   is_deeply( \@methods,
              [
                 [ goto => 4, 0 ],
                 [ erasech => 5, 1,     { bg => 2 } ],
                 [ erasech => 5, undef, { bg => 3 } ],
              ],
              'RC erase with implied pen' );
   undef @methods;

   # cheating
   $rc->setpen( undef );
}

# erase with translation
{
   $rc->translate( 3, 5 );

   $rc->erase_at( 0, 0, 5, Tickit::Pen->new( bg => 1 ) );

   $rc->goto( 1, 0 );
   $rc->erase( 5, Tickit::Pen->new( bg => 2 ) );

   $rc->render_to_window( $win );
   is_deeply( \@methods,
              [
                 [ goto => 3, 5 ],
                 [ erasech => 5, undef, { bg => 1 } ],
                 [ goto => 4, 5 ],
                 [ erasech => 5, undef, { bg => 2 } ],
              ],
              'RC erase with translation' );
   undef @methods;

   $rc->translate( -3, -5 );
}

# clear
{
   $rc->clear( Tickit::Pen->new( bg => 3 ) );

   $rc->render_to_window( $win );
   is_deeply( \@methods,
              [
               ( map {
                 [ goto => $_, 0 ],
                 [ erasech => 20, undef, { bg => 3 } ] } 0 .. 9 )
              ],
              'RC renders clear' );
   undef @methods;
}

done_testing;
