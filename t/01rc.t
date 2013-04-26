#!/usr/bin/perl

use strict;
use warnings;

use Test::More;

use Tickit::RenderContext;

use Tickit::Pen;

my $rc = Tickit::RenderContext->new(
   lines => 10,
   cols  => 20,
);

isa_ok( $rc, "Tickit::RenderContext", '$rc isa Tickit::RenderContext' );

is( $rc->lines, 10, '$rc->lines' );
is( $rc->cols,  20, '$rc->cols' );

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

# Initially empty
{
   $rc->render_to_window( $win );

   is_deeply( \@methods,
              [],
              'Empty RC renders nothing' );
}

# Text
{
   $rc->text_at( 2, 5, "Hello, world!", Tickit::Pen->new );

   $rc->render_to_window( $win );

   is_deeply( \@methods,
              [
                 [ goto => 2, 5 ],
                 [ print => "Hello, world!", {} ],
              ],
              'RC renders text' );
   undef @methods;

   $rc->render_to_window( $win );
   is_deeply( \@methods, [], 'RC now empty after render' );
   undef @methods;

   $rc->text_at( 3, 0, "Some long text", Tickit::Pen->new( fg => 1 ) );
   $rc->text_at( 3, 5, "more", Tickit::Pen->new( fg => 2 ) );

   $rc->render_to_window( $win );
   is_deeply( \@methods,
              [
                 [ goto => 3, 0 ],
                 [ print => "Some ", { fg => 1 } ],
                 [ print => "more", { fg => 2 } ],
                 [ print => " text", { fg => 1 } ],
              ],
              'RC renders overwritten text' );
   undef @methods;
}

# Erase
{
   $rc->erase_at( 0, 0, 20, Tickit::Pen->new( fg => 5 ) );
   $rc->erase_at( 0, 5, 10, Tickit::Pen->new( fg => 5, b => 1 ) );

   $rc->render_to_window( $win );

   is_deeply( \@methods,
              [
                 [ goto => 0, 0 ],
                 [ erase =>  5, { fg => 5         }, 1 ],
                 [ erase => 10, { fg => 5, b => 1 }, 1 ],
                 [ erase =>  5, { fg => 5         }, undef ],
              ],
              'RC renders erase' );
   undef @methods;
}

# Clear
{
   $rc->clear( Tickit::Pen->new( bg => 3 ) );

   $rc->render_to_window( $win );

   is_deeply( \@methods,
              [
               ( map {
                 [ goto => $_, 0 ],
                 [ erase => 20, { bg => 3 }, undef ] } 0 .. 9 )
              ],
              'RC renders clear' );
   undef @methods;
}

# Clipping
{
   my $pen = Tickit::Pen->new;

   $rc->text_at( -1, 5, "TTTTTTTTTT", $pen );
   $rc->text_at( 11, 5, "BBBBBBBBBB", $pen );
   $rc->text_at( 4, -3, "LLLLLLLLLL", $pen );
   $rc->text_at( 5, 15, "RRRRRRRRRR", $pen );

   $rc->render_to_window( $win );
   is_deeply( \@methods,
              [
                 [ goto => 4, 0 ],
                 [ print => "LLLLLLL", {} ],
                 [ goto => 5, 15 ],
                 [ print => "RRRRR", {} ],
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
                 [ erase => 7, { fg => 3 }, 1 ], # TODO: this 1 should not be here
                 [ goto => 5, 15 ],
                 [ erase => 5, { fg => 4 }, undef ],
              ],
              'RC text rendering with clipping' );
   undef @methods;
}

done_testing;
