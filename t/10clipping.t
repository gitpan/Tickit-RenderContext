#!/usr/bin/perl

use strict;
use warnings;

use Test::More;
use t::TestWindow qw( $win @methods );

use Tickit::RenderContext;

use Tickit::Pen;
use Tickit::Rect;

my $rc = Tickit::RenderContext->new(
   lines => 10,
   cols  => 20,
);

# Clipping to edge
{
   my $pen = Tickit::Pen->new;

   $rc->text_at( -1, 5, "TTTTTTTTTT", $pen );
   $rc->text_at( 11, 5, "BBBBBBBBBB", $pen );
   $rc->text_at( 4, -3, "[LLLLLLLL]", $pen );
   $rc->text_at( 5, 15, "[RRRRRRRR]", $pen );

   $rc->render_to_window( $win );
   is_deeply( \@methods,
              [
                 [ goto => 4, 0 ],
                 [ print => "LLLLLL]", {} ],
                 [ goto => 5, 15 ],
                 [ print => "[RRRR", {} ],
              ],
              'RC text rendering with clipping' );
   undef @methods;

   $rc->erase_at( -1, 5, 10, Tickit::Pen->new( fg => 1 ) );
   $rc->erase_at( 11, 5, 10, Tickit::Pen->new( fg => 2 ) );
   $rc->erase_at( 4, -3, 10, Tickit::Pen->new( fg => 3 ) );
   $rc->erase_at( 5, 15, 10, Tickit::Pen->new( fg => 4 ) );

   $rc->render_to_window( $win );
   is_deeply( \@methods,
              [
                 [ goto => 4, 0 ],
                 [ erasech => 7, undef, { fg => 3 } ],
                 [ goto => 5, 15 ],
                 [ erasech => 5, undef, { fg => 4 } ],
              ],
              'RC text rendering with clipping' );
   undef @methods;
}

# Clipping to rect
{
   my $pen = Tickit::Pen->new;

   $rc->clip( Tickit::Rect->new(
         top => 2,
         left => 2,
         bottom => 8,
         right => 18
   ) );

   $rc->text_at( 1, 5, "TTTTTTTTTT", $pen );
   $rc->text_at( 9, 5, "BBBBBBBBBB", $pen );
   $rc->text_at( 4, -3, "[LLLLLLLL]", $pen );
   $rc->text_at( 5, 15, "[RRRRRRRR]", $pen );

   $rc->render_to_window( $win );
   is_deeply( \@methods,
              [
                 [ goto => 4, 2 ],
                 [ print => "LLLL]", {} ],
                 [ goto => 5, 15 ],
                 [ print => "[RR", {} ],
              ],
              'RC text rendering with clipping' );
   undef @methods;

   $rc->clip( Tickit::Rect->new(
         top => 2,
         left => 2,
         bottom => 8,
         right => 18
   ) );

   $rc->erase_at( 1, 5, 10, Tickit::Pen->new( fg => 1 ) );
   $rc->erase_at( 9, 5, 10, Tickit::Pen->new( fg => 2 ) );
   $rc->erase_at( 4, -3, 10, Tickit::Pen->new( fg => 3 ) );
   $rc->erase_at( 5, 15, 10, Tickit::Pen->new( fg => 4 ) );

   $rc->render_to_window( $win );
   is_deeply( \@methods,
              [
                 [ goto => 4, 2 ],
                 [ erasech => 5, undef, { fg => 3 } ],
                 [ goto => 5, 15 ],
                 [ erasech => 3, undef, { fg => 4 } ],
              ],
              'RC text rendering with clipping' );
   undef @methods;
}

# clipping with translation
{
   $rc->translate( 3, 5 );

   $rc->clip( Tickit::Rect->new(
         top   => 2,
         left  => 2,
         lines => 3,
         cols  => 5
   ) );

   $rc->text_at( $_, 0, "$_"x10, Tickit::Pen->new ) for 0 .. 8;

   $rc->render_to_window( $win );
   is_deeply( \@methods,
              [
                 [ goto => 5, 7 ],
                 [ print => "22222", {} ],
                 [ goto => 6, 7 ],
                 [ print => "33333", {} ],
                 [ goto => 7, 7 ],
                 [ print => "44444", {} ],
              ],
              'RC clipping rectangle translated' );
   undef @methods;

   $rc->translate( -3, -5 );
}

done_testing;
