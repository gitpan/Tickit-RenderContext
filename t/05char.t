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

my $pen = Tickit::Pen->new;

# Characters
{
   $rc->char_at( 5, 5, 0x41, $pen );
   $rc->char_at( 5, 6, 0x42, $pen );
   $rc->char_at( 5, 7, 0x43, $pen );

   $rc->render_to_window( $win );
   is_deeply( \@methods,
              [
                 [ goto => 5, 5 ],
                 [ print => "A", {} ],
                 [ print => "B", {} ],
                 [ print => "C", {} ],
              ],
              'RC renders char_at' );
   undef @methods;
}

# Characters with translation
{
   $rc->translate( 3, 5 );

   $rc->char_at( 1, 1, 0x31, $pen );
   $rc->char_at( 1, 2, 0x32, $pen );

   $rc->render_to_window( $win );
   is_deeply( \@methods,
              [
                 [ goto => 4, 6 ],
                 [ print => "1", {} ],
                 [ print => "2", {} ],
              ],
              'RC renders char_at with translation' );
   undef @methods;

   $rc->translate( -3, -5 );
}

done_testing;
