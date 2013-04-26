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
   sub erasech { shift; push @methods, [ erasech => $_[0], $_[1], { $_[2]->getattrs } ];
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

   $rc->goto( 4, 2 );
   $rc->text( "Text in ", Tickit::Pen->new );
   $rc->text( "bold", Tickit::Pen->new( b => 1 ) );

   $rc->render_to_window( $win );
   is_deeply( \@methods,
              [
                 [ goto => 4, 2 ],
                 [ print => "Text in ", {} ],
                 [ print => "bold", { b => 1 } ],
              ],
              'RC text with virtual-cursor' );
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
                 [ erasech =>  5, 1,     { fg => 5         } ],
                 [ erasech => 10, 1,     { fg => 5, b => 1 } ],
                 [ erasech =>  5, undef, { fg => 5         } ],
              ],
              'RC renders erase' );
   undef @methods;

   $rc->goto( 2, 6 );
   $rc->erase( 12, Tickit::Pen->new( u => 1 ) );
   $rc->goto( 3, 12 );
   $rc->erase_to( 16, Tickit::Pen->new( i => 1 ) );

   $rc->render_to_window( $win );
   is_deeply( \@methods,
              [
                 [ goto => 2, 6 ],
                 [ erasech => 12, 1, { u => 1 } ],
                 [ goto => 3, 12 ],
                 [ erasech => 4, 1, { i => 1 } ],
              ],
              'RC erase with virtual-cursor' );
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
                 [ erasech => 20, undef, { bg => 3 } ] } 0 .. 9 )
              ],
              'RC renders clear' );
   undef @methods;
}

# Skipping
{
   my $pen = Tickit::Pen->new;

   $rc->text_at( 6, 1, "This will be skipped", $pen );
   $rc->skip_at( 6, 10, 4 );

   $rc->erase_at( 7, 5, 15, $pen );
   $rc->skip_at( 7, 10, 2 );

   $rc->render_to_window( $win );
   is_deeply( \@methods,
              [
                 [ goto => 6, 1 ],
                 [ print => "This will", {} ],
                 [ goto => 6, 14 ],
                 [ print => "skippe", {} ],
                 [ goto => 7, 5 ],
                 [ erasech => 5, 1, {} ],
                 [ goto => 7, 12 ],
                 [ erasech => 8, undef, {} ],
              ],
              'RC skipping' );
   undef @methods;

   $rc->goto( 8, 0 );
   $rc->text( "Some", $pen );
   $rc->skip( 2 );
   $rc->text( "more", $pen );
   $rc->skip_to( 14 );
   $rc->text( "14", $pen );

   $rc->render_to_window( $win );
   is_deeply( \@methods,
              [
                 [ goto => 8, 0 ],
                 [ print => "Some", {} ],
                 [ goto => 8, 6 ],
                 [ print => "more", {} ],
                 [ goto => 8, 14 ],
                 [ print => "14", {} ],
              ],
              'RC skipping at virtual-cursor' );
   undef @methods;
}

done_testing;
