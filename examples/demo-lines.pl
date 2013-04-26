#!/usr/bin/perl

use strict;
use warnings;

use Tickit;

Tickit->new( root => RenderContextDemo->new )->run;

package RenderContextDemo;
use base qw( Tickit::Widget );
use Tickit::RenderContext qw(
   LINE_SINGLE LINE_DOUBLE LINE_THICK
   CAP_START CAP_END CAP_BOTH
);

sub lines { 1 }
sub cols  { 1 }

use constant CLEAR_BEFORE_RENDER => 0;

sub grid_at
{
   my ( $rc, $line, $col, $style, $pen ) = @_;

   # A 2x2 grid of cells
   $rc->hline_at( $line + 0, $col, $col + 12, $style, $pen );
   $rc->hline_at( $line + 3, $col, $col + 12, $style, $pen );
   $rc->hline_at( $line + 6, $col, $col + 12, $style, $pen );

   $rc->vline_at( $line + 0, $line + 6, $col +  0, $style, $pen );
   $rc->vline_at( $line + 0, $line + 6, $col +  6, $style, $pen );
   $rc->vline_at( $line + 0, $line + 6, $col + 12, $style, $pen );
}

sub corner_at
{
   my ( $rc, $line, $col, $style_horiz, $style_vert, $pen ) = @_;

   $rc->hline_at( $line, $col, $col + 2, $style_horiz, $pen, CAP_END );
   $rc->vline_at( $line, $line + 1, $col, $style_vert, $pen, CAP_END );
}

sub render
{
   my $self = shift;
   my %args = @_;
   my $win = $self->window or return;

   my $rc = Tickit::RenderContext->new( lines => $win->lines, cols => $win->cols );
   $rc->clip( $args{rect} );

   $rc->text_at( 1, 2, "Single", $self->pen );
   grid_at( $rc, 2,  2, LINE_SINGLE, Tickit::Pen->new( fg => "red" ) );

   $rc->text_at( 1, 22, "Double", $self->pen );
   grid_at( $rc, 2, 22, LINE_DOUBLE, Tickit::Pen->new( fg => "green" ) );

   $rc->text_at( 1, 42, "Thick", $self->pen );
   grid_at( $rc, 2, 42, LINE_THICK, Tickit::Pen->new( fg => "blue" ) );

   my $pen;

   # Possible line interactions: crosses
   $pen = Tickit::Pen->new( fg => "cyan" );
   $rc->text_at( 10, 2, "Crossings", $self->pen );
   $rc->hline_at( 12,  4, 14, LINE_SINGLE, $pen, CAP_BOTH );
   $rc->hline_at( 15,  4, 14, LINE_DOUBLE, $pen, CAP_BOTH );
   $rc->hline_at( 18,  4, 14, LINE_THICK,  $pen, CAP_BOTH );
   $rc->vline_at( 12, 18,  5, LINE_SINGLE, $pen, CAP_BOTH );
   $rc->vline_at( 12, 18,  9, LINE_DOUBLE, $pen, CAP_BOTH );
   $rc->vline_at( 12, 18, 13, LINE_THICK,  $pen, CAP_BOTH );

   # T-junctions
   $pen = Tickit::Pen->new( fg => "magenta" );
   $rc->text_at( 10, 24, "T junctions", $self->pen );
   $rc->hline_at( 11, 25, 35, LINE_SINGLE, $pen, CAP_BOTH );
   $rc->hline_at( 14, 25, 35, LINE_DOUBLE, $pen, CAP_BOTH );
   $rc->hline_at( 17, 25, 35, LINE_THICK,  $pen, CAP_BOTH );
   $rc->vline_at( 11, 12, 26, LINE_SINGLE, $pen, CAP_END );
   $rc->vline_at( 11, 12, 30, LINE_DOUBLE, $pen, CAP_END );
   $rc->vline_at( 11, 12, 34, LINE_THICK,  $pen, CAP_END );
   $rc->vline_at( 14, 15, 26, LINE_SINGLE, $pen, CAP_END );
   $rc->vline_at( 14, 15, 30, LINE_DOUBLE, $pen, CAP_END );
   $rc->vline_at( 14, 15, 34, LINE_THICK,  $pen, CAP_END );
   $rc->vline_at( 17, 18, 26, LINE_SINGLE, $pen, CAP_END );
   $rc->vline_at( 17, 18, 30, LINE_DOUBLE, $pen, CAP_END );
   $rc->vline_at( 17, 18, 34, LINE_THICK,  $pen, CAP_END );

   # Corners
   $pen = Tickit::Pen->new( fg => "yellow" );
   $rc->text_at( 10, 42, "Corners", $self->pen );
   corner_at( $rc, 11, 44, LINE_SINGLE, LINE_SINGLE, $pen );
   corner_at( $rc, 11, 50, LINE_SINGLE, LINE_DOUBLE, $pen );
   corner_at( $rc, 11, 56, LINE_SINGLE, LINE_THICK,  $pen );
   corner_at( $rc, 14, 44, LINE_DOUBLE, LINE_SINGLE, $pen );
   corner_at( $rc, 14, 50, LINE_DOUBLE, LINE_DOUBLE, $pen );
   corner_at( $rc, 14, 56, LINE_DOUBLE, LINE_THICK,  $pen );
   corner_at( $rc, 17, 44, LINE_THICK,  LINE_SINGLE, $pen );
   corner_at( $rc, 17, 50, LINE_THICK,  LINE_DOUBLE, $pen );
   corner_at( $rc, 17, 56, LINE_THICK,  LINE_THICK,  $pen );

   $rc->render_to_window( $win );
}
