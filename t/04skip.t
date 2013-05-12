#!/usr/bin/perl

use strict;
use warnings;

use Test::More;
use t::TestWindow qw( $win @methods );

use Tickit::RenderContext;

my $rc = Tickit::RenderContext->new(
   lines => 10,
   cols  => 20,
);

my $pen = Tickit::Pen->new;

# skip_at
{
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

# skip VC
{
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

done_testing;
