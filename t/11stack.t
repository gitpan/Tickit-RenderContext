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

my $pen = Tickit::Pen->new;

# position
{
   $rc->goto( 2, 2 );

   {
      $rc->save;

      $rc->goto( 4, 4 );

      $rc->restore;
   }

   $rc->text( "some text", $pen );

   $rc->render_to_window( $win );

   is_deeply( \@methods,
              [
                 [ goto => 2, 2 ],
                 [ print => "some text", {} ],
              ],
              'Stack saves/restores virtual cursor position' );
   undef @methods;
}

# clipping
{
   $rc->text_at( 0, 0, "0000000000", $pen );

   {
      $rc->save;
      $rc->clip( Tickit::Rect->new( top => 0, left => 2, lines => 10, cols => 16 ) );

      $rc->text_at( 1, 0, "1111111111", $pen );

      $rc->restore;
   }

   $rc->text_at( 2, 0, "2222222222", $pen );

   $rc->render_to_window( $win );

   is_deeply( \@methods,
              [
                 [ goto => 0, 0 ],
                 [ print => "0000000000", {} ],
                 [ goto => 1, 2 ],
                 [ print => "11111111", {} ],
                 [ goto => 2, 0 ],
                 [ print => "2222222222", {} ],
              ],
              'Stack saves/restores clipping region' );
   undef @methods;
}

# pen
{
   $rc->save;
   {
      $rc->goto( 3, 0 );

      $rc->setpen( Tickit::Pen->new( bg => 1 ) );
      $rc->text( "123" );

      {
         $rc->savepen;

         $rc->setpen( Tickit::Pen->new( fg => 4 ) );
         $rc->text( "456" );

         $rc->restore;
      }

      $rc->text( "789" );
   }
   $rc->restore;

   $rc->render_to_window( $win );

   is_deeply( \@methods,
              [
                 [ goto => 3, 0 ],
                 [ print => "123", { bg => 1 } ],
                 [ print => "456", { bg => 1, fg => 4 } ],
                 [ print => "789", { bg => 1 } ],
              ],
              'Stack saves/restores render pen' );
   undef @methods;
}

# translation
{
   $rc->text_at( 0, 0, "A", $pen );

   $rc->save;
   {
      $rc->translate( 2, 2 );

      $rc->text_at( 1, 1, "B", $pen );
   }
   $rc->restore;

   $rc->text_at( 2, 2, "C", $pen );

   $rc->render_to_window( $win );

   is_deeply( \@methods,
              [
                 [ goto => 0, 0 ],
                 [ print => "A", {} ],
                 [ goto => 2, 2 ],
                 [ print => "C", {} ],
                 [ goto => 3, 3 ],
                 [ print => "B", {} ],
              ],
              'Stack saves/restores translation offset' );
   undef @methods;
}

done_testing;
