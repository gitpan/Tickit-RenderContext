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

isa_ok( $rc, "Tickit::RenderContext", '$rc isa Tickit::RenderContext' );

is( $rc->lines, 10, '$rc->lines' );
is( $rc->cols,  20, '$rc->cols' );

# Initially empty
{
   $rc->flush_to_window( $win );

   is_deeply( \@methods,
              [],
              'Empty RC renders nothing' );
}

# Absolute spans
{
   # Direct pen
   my $pen = Tickit::Pen->new( fg => 1 );
   $rc->text_at( 0, 1, "text span", $pen );
   $rc->erase_at( 1, 1, 5, $pen );

   # Stored pen
   $rc->setpen( Tickit::Pen->new( bg => 2 ) );
   $rc->text_at( 2, 1, "another span" );
   $rc->erase_at( 3, 1, 10 );

   # Combined pens
   $rc->text_at( 4, 1, "third span", $pen );
   $rc->erase_at( 5, 1, 7, $pen );

   $rc->flush_to_window( $win );

   is_deeply( \@methods,
              [
                 [ goto => 0, 1 ], [ print => "text span", { fg => 1 } ],
                 [ goto => 1, 1 ], [ erasech => 5, undef, { fg => 1 } ],
                 [ goto => 2, 1 ], [ print => "another span", { bg => 2 } ],
                 [ goto => 3, 1 ], [ erasech => 10, undef, { bg => 2 } ],
                 [ goto => 4, 1 ], [ print => "third span", { fg => 1, bg => 2 } ],
                 [ goto => 5, 1 ], [ erasech => 7, undef, { fg => 1, bg => 2 } ],
              ],
              'RC renders text' );
   undef @methods;

   # cheating
   $rc->setpen( undef );

   $rc->flush_to_window( $win );
   is_deeply( \@methods, [], 'RC now empty after render' );
   undef @methods;
}

# Span splitting
{
   my $pen = Tickit::Pen->new;
   my $pen2 = Tickit::Pen->new( b => 1 );

   # aaaAAaaa
   $rc->text_at( 0, 0, "aaaaaaaa", $pen );
   $rc->text_at( 0, 3, "AA", $pen2 );

   # BBBBBBBB
   $rc->text_at( 1, 2, "bbbb", $pen );
   $rc->text_at( 1, 0, "BBBBBBBB", $pen2 );

   # cccCCCCC
   $rc->text_at( 2, 0, "cccccc", $pen );
   $rc->text_at( 2, 3, "CCCCC", $pen2 );

   # DDDDDddd
   $rc->text_at( 3, 2, "dddddd", $pen );
   $rc->text_at( 3, 0, "DDDDD", $pen2 );

   $rc->flush_to_window( $win );
   is_deeply( \@methods,
              [
                 [ goto => 0, 0 ], [ print => "aaa", {} ], [ print => "AA", { b => 1 } ], [ print => "aaa", {} ],
                 [ goto => 1, 0 ], [ print => "BBBBBBBB", { b => 1 } ],
                 [ goto => 2, 0 ], [ print => "ccc", {} ], [ print => "CCCCC", { b => 1 } ],
                 [ goto => 3, 0 ], [ print => "DDDDD", { b => 1 } ], [ print => "ddd", {} ],
              ],
              'RC spans can be split' );
   undef @methods;
}

{
   my $pen = Tickit::Pen->new;
   $rc->text_at( 0, 0, "abcdefghijkl", $pen );
   $rc->text_at( 0, $_, "-", $pen ) for 2, 4, 6, 8;

   $rc->flush_to_window( $win );
   is_deeply( \@methods,
              [
                 [ goto => 0, 0 ],
                 [ print => "ab", {} ],
                 [ print => "-", {} ], # c
                 [ print => "d", {} ],
                 [ print => "-", {} ], # e
                 [ print => "f", {} ],
                 [ print => "-", {} ], # g
                 [ print => "h", {} ],
                 [ print => "-", {} ], # i
                 [ print => "jkl", {} ],
              ],
              'RC renders overwritten text split chunks' );
   undef @methods;
}

# Absolute skipping
{
   my $pen = Tickit::Pen->new;
   $rc->text_at( 6, 1, "This will be skipped", $pen );
   $rc->skip_at( 6, 10, 4 );

   $rc->erase_at( 7, 5, 15, $pen );
   $rc->skip_at( 7, 10, 2 );

   $rc->flush_to_window( $win );
   is_deeply( \@methods,
              [
                 [ goto => 6, 1 ],
                 [ print => "This will", {} ],
                 [ goto => 6, 14 ],
                 [ print => "skippe", {} ],
                 [ goto => 7, 5 ],
                 [ erasech => 5, undef, {} ],
                 [ goto => 7, 12 ],
                 [ erasech => 8, undef, {} ],
              ],
              'RC skipping' );
   undef @methods;
}

# VC spans
{
   # Direct pen
   my $pen = Tickit::Pen->new( fg => 3 );
   $rc->goto( 0, 2 ); $rc->text( "text span", $pen );
   $rc->goto( 1, 2 ); $rc->erase( 5, $pen );

   # Stored pen
   $rc->setpen( Tickit::Pen->new( bg => 4 ) );
   $rc->goto( 2, 2 ); $rc->text( "another span" );
   $rc->goto( 3, 2 ); $rc->erase( 10 );

   # Combined pens
   $rc->goto( 4, 2 ); $rc->text( "third span", $pen );
   $rc->goto( 5, 2 ); $rc->erase( 7, $pen );

   $rc->flush_to_window( $win );

   is_deeply( \@methods,
              [
                 [ goto => 0, 2 ], [ print => "text span", { fg => 3 } ],
                 [ goto => 1, 2 ], [ erasech => 5, undef, { fg => 3 } ],
                 [ goto => 2, 2 ], [ print => "another span", { bg => 4 } ],
                 [ goto => 3, 2 ], [ erasech => 10, undef, { bg => 4 } ],
                 [ goto => 4, 2 ], [ print => "third span", { fg => 3, bg => 4 } ],
                 [ goto => 5, 2 ], [ erasech => 7, undef, { fg => 3, bg => 4 } ],
              ],
              'RC renders text' );
   undef @methods;

   # cheating
   $rc->setpen( undef );
}

# VC skipping
{
   my $pen = Tickit::Pen->new;
   $rc->goto( 8, 0 );
   $rc->text( "Some", $pen );
   $rc->skip( 2 );
   $rc->text( "more", $pen );
   $rc->skip_to( 14 );
   $rc->text( "14", $pen );

   $rc->flush_to_window( $win );
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

# Translation
{
   $rc->translate( 3, 5 );

   $rc->text_at( 0, 0, "at 0,0", Tickit::Pen->new );

   $rc->goto( 1, 0 );
   $rc->text( "at 1,0", Tickit::Pen->new );

   $rc->flush_to_window( $win );
   is_deeply( \@methods,
              [
                 [ goto => 3, 5 ],
                 [ print => "at 0,0", {} ],
                 [ goto => 4, 5 ],
                 [ print => "at 1,0", {} ],
              ],
              'RC renders text with translation' );
   undef @methods;

   $rc->translate( -3, -5 );
}

# Clear
{
   $rc->clear( Tickit::Pen->new( bg => 3 ) );

   $rc->flush_to_window( $win );
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
