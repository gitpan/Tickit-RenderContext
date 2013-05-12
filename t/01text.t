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
   $rc->render_to_window( $win );

   is_deeply( \@methods,
              [],
              'Empty RC renders nothing' );
}

# text_at
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

   my $pen = Tickit::Pen->new;
   $rc->text_at( 0, 0, "abcdefghijkl", $pen );
   $rc->text_at( 0, $_, "-", $pen ) for 2, 4, 6, 8;

   $rc->render_to_window( $win );
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

# text VC explicit pen
{
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

# text VC setpen
{
   $rc->goto( 5, 0 );
   $rc->setpen( Tickit::Pen->new( i => 1 ) );
   $rc->text( "italics" );
   $rc->setpen( Tickit::Pen->new( u => 1 ) );
   $rc->text( " underline" );

   $rc->render_to_window( $win );
   is_deeply( \@methods,
              [
                 [ goto => 5, 0 ],
                 [ print => "italics", { i => 1 } ],
                 [ print => " underline", { u => 1 } ],
              ],
              'RC renders text with implied pen' );
   undef @methods;

   # cheating
   $rc->setpen( undef );
}

# text with translation
{
   $rc->translate( 3, 5 );

   $rc->text_at( 0, 0, "at 0,0", Tickit::Pen->new );

   $rc->goto( 1, 0 );
   $rc->text( "at 1,0", Tickit::Pen->new );

   $rc->render_to_window( $win );
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

done_testing;
