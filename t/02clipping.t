#!/usr/bin/perl

use strict;
use warnings;

use Test::More;

use Tickit::RenderContext;

use Tickit::Pen;
use Tickit::Rect;

my $rc = Tickit::RenderContext->new(
   lines => 10,
   cols  => 20,
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
   sub erasech { shift; push @methods, [ erasech => $_[0], $_[1], { $_[2]->getattrs } ];
               return Tickit::StringPos->limit_columns( $_[0] ); }
}
my $win = bless [], "TestWindow";

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
                 [ erasech => 7, 1,     { fg => 3 } ], # TODO: this 1 should not be here
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

   $rc->erase_at( 1, 5, 10, Tickit::Pen->new( fg => 1 ) );
   $rc->erase_at( 9, 5, 10, Tickit::Pen->new( fg => 2 ) );
   $rc->erase_at( 4, -3, 10, Tickit::Pen->new( fg => 3 ) );
   $rc->erase_at( 5, 15, 10, Tickit::Pen->new( fg => 4 ) );

   $rc->render_to_window( $win );
   is_deeply( \@methods,
              [
                 [ goto => 4, 2 ],
                 [ erasech => 5, 1, { fg => 3 } ], # TODO: this 1 should not be here
                 [ goto => 5, 15 ],
                 [ erasech => 3, 1, { fg => 4 } ],
              ],
              'RC text rendering with clipping' );
   undef @methods;
}

done_testing;
