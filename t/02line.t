#!/usr/bin/perl

use strict;
use warnings;
use utf8;

use Test::More;

use Tickit::RenderContext qw( LINE_SINGLE );

use Tickit::Pen;

my $rc = Tickit::RenderContext->new(
   lines => 30,
   cols  => 30,
);

my @methods;
{
   package TestWindow;
   use Tickit::Utils qw( string_count );
   use Tickit::StringPos;

   sub goto { shift; push @methods, [ goto => @_ ] }
   sub print { shift; push @methods, [ print => $_[0], { $_[1]->getattrs } ];
               string_count( $_[0], my $pos = Tickit::StringPos->zero );
               return $pos; }
   sub erase { shift; push @methods, [ erase => $_[0], { $_[1]->getattrs }, $_[2] ];
               return Tickit::StringPos->limit_columns( $_[0] ); }
}
my $win = bless [], "TestWindow";

my $pen = Tickit::Pen->new;

# Simple lines
{
   $rc->hline( 10, 10, 20, LINE_SINGLE, $pen );
   $rc->hline( 20, 10, 20, LINE_SINGLE, $pen );

   $rc->render_to_window( $win );
   is_deeply( \@methods,
              [
                 [ goto => 10, 10 ],
                 [ print => "╶", {} ],
               ( [ print => "─", {} ] ) x 9,
                 [ print => "╴", {} ],
                 [ goto => 20, 10 ],
                 [ print => "╶", {} ],
               ( [ print => "─", {} ] ) x 9,
                 [ print => "╴", {} ],
              ],
              'RC renders hlines' );
   undef @methods;

   $rc->vline( 10, 20, 10, LINE_SINGLE, $pen );
   $rc->vline( 10, 20, 20, LINE_SINGLE, $pen );

   $rc->render_to_window( $win );
   is_deeply( \@methods,
              [
                 [ goto => 10, 10 ],
                 [ print => "╷", {} ],
                 [ goto => 10, 20 ],
                 [ print => "╷", {} ],
               ( map {
                 [ goto => $_, 10 ],
                 [ print => "│", {} ],
                 [ goto => $_, 20 ],
                 [ print => "│", {} ] } 11 .. 19 ),
                 [ goto => 20, 10 ],
                 [ print => "╵", {} ],
                 [ goto => 20, 20 ],
                 [ print => "╵", {} ],
              ],
              'RC renders vlines' );
   undef @methods;
}

# Line merging
{
   $rc->hline( 10, 10, 14, LINE_SINGLE, $pen );
   $rc->hline( 12, 10, 14, LINE_SINGLE, $pen );
   $rc->hline( 14, 10, 14, LINE_SINGLE, $pen );
   $rc->vline( 10, 14, 10, LINE_SINGLE, $pen );
   $rc->vline( 10, 14, 12, LINE_SINGLE, $pen );
   $rc->vline( 10, 14, 14, LINE_SINGLE, $pen );

   $rc->render_to_window( $win );
   is_deeply( \@methods,
              [
                 [ goto => 10, 10 ],
                 [ print => "┌", {} ],
                 [ print => "─", {} ],
                 [ print => "┬", {} ],
                 [ print => "─", {} ],
                 [ print => "┐", {} ],
                 [ goto => 11, 10 ],
                 [ print => "│", {} ],
                 [ goto => 11, 12 ],
                 [ print => "│", {} ],
                 [ goto => 11, 14 ],
                 [ print => "│", {} ],
                 [ goto => 12, 10 ],
                 [ print => "├", {} ],
                 [ print => "─", {} ],
                 [ print => "┼", {} ],
                 [ print => "─", {} ],
                 [ print => "┤", {} ],
                 [ goto => 13, 10 ],
                 [ print => "│", {} ],
                 [ goto => 13, 12 ],
                 [ print => "│", {} ],
                 [ goto => 13, 14 ],
                 [ print => "│", {} ],
                 [ goto => 14, 10 ],
                 [ print => "└", {} ],
                 [ print => "─", {} ],
                 [ print => "┴", {} ],
                 [ print => "─", {} ],
                 [ print => "┘", {} ],
              ],
              'RC renders line merging' );
   undef @methods;
}

done_testing;
