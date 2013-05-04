#!/usr/bin/perl

use strict;
use warnings;
use utf8;

use Test::More;
use t::TestWindow qw( $win @methods );

use Tickit::RenderContext qw( LINE_SINGLE CAP_START CAP_END CAP_BOTH );

use Tickit::Pen;

my $rc = Tickit::RenderContext->new(
   lines => 30,
   cols  => 30,
);

my $pen = Tickit::Pen->new;

# Simple lines
{
   $rc->hline_at( 10, 10, 20, LINE_SINGLE, $pen );
   $rc->hline_at( 11, 10, 20, LINE_SINGLE, $pen, CAP_START );
   $rc->hline_at( 12, 10, 20, LINE_SINGLE, $pen, CAP_END );
   $rc->hline_at( 13, 10, 20, LINE_SINGLE, $pen, CAP_BOTH );

   $rc->render_to_window( $win );
   is_deeply( \@methods,
              [
                 [ goto => 10, 10 ],
                 [ print => "╶" . ( "─" x 9 ) . "╴", {} ],
                 [ goto => 11, 10 ],
                 [ print => ( "─" x 10 ) . "╴", {} ],
                 [ goto => 12, 10 ],
                 [ print => "╶" . ( "─" x 10 ), {} ],
                 [ goto => 13, 10 ],
                 [ print => ( "─" x 11 ), {} ],
              ],
              'RC renders hline_ats' );
   undef @methods;

   $rc->vline_at( 10, 20, 10, LINE_SINGLE, $pen );
   $rc->vline_at( 10, 20, 11, LINE_SINGLE, $pen, CAP_START );
   $rc->vline_at( 10, 20, 12, LINE_SINGLE, $pen, CAP_END );
   $rc->vline_at( 10, 20, 13, LINE_SINGLE, $pen, CAP_BOTH );

   $rc->render_to_window( $win );
   is_deeply( \@methods,
              [
                 [ goto => 10, 10 ],
                 [ print => "╷│╷│", {} ],
               ( map {
                 [ goto => $_, 10 ],
                 [ print => "││││", {} ] } 11 .. 19 ),
                 [ goto => 20, 10 ],
                 [ print => "╵╵││", {} ],
              ],
              'RC renders vline_ats' );
   undef @methods;
}

# Line merging
{
   $rc->hline_at( 10, 10, 14, LINE_SINGLE, $pen );
   $rc->hline_at( 12, 10, 14, LINE_SINGLE, $pen );
   $rc->hline_at( 14, 10, 14, LINE_SINGLE, $pen );
   $rc->vline_at( 10, 14, 10, LINE_SINGLE, $pen );
   $rc->vline_at( 10, 14, 12, LINE_SINGLE, $pen );
   $rc->vline_at( 10, 14, 14, LINE_SINGLE, $pen );

   $rc->render_to_window( $win );
   is_deeply( \@methods,
              [
                 [ goto => 10, 10 ],
                 [ print => "┌─┬─┐", {} ],
                 [ goto => 11, 10 ],
                 [ print => "│", {} ],
                 [ goto => 11, 12 ],
                 [ print => "│", {} ],
                 [ goto => 11, 14 ],
                 [ print => "│", {} ],
                 [ goto => 12, 10 ],
                 [ print => "├─┼─┤", {} ],
                 [ goto => 13, 10 ],
                 [ print => "│", {} ],
                 [ goto => 13, 12 ],
                 [ print => "│", {} ],
                 [ goto => 13, 14 ],
                 [ print => "│", {} ],
                 [ goto => 14, 10 ],
                 [ print => "└─┴─┘", {} ],
              ],
              'RC renders line merging' );
   undef @methods;
}

done_testing;
