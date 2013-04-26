#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2013 -- leonerd@leonerd.org.uk

package Tickit::RenderContext;

use strict;
use warnings;
use feature qw( switch );

our $VERSION = '0.01';

use Tickit::Utils qw( textwidth substrwidth string_count );
use Tickit::StringPos;

# Exported API constants
use Exporter 'import';
our @EXPORT_OK = qw( LINE_SINGLE LINE_DOUBLE LINE_THICK );
use constant {
   LINE_SINGLE => 0x01,
   LINE_DOUBLE => 0x02,
   LINE_THICK  => 0x03,
};

# cell states
use constant {
   SKIP  => 0,
   TEXT  => 1,
   ERASE => 2,
   CONT  => 3,
   LINE  => 4,
};

=head1 NAME

C<Tickit::RenderContext> - efficiently render text and linedrawing on
L<Tickit> windows

=head1 SYNOPSIS

 package Tickit::Widget::Something;
 ...

 sub render
 {
    my $self = shift;
    my $win = $self->window or return;

    my $rc = Tickit::RenderContext->new(
       lines => $win->lines,
       cols  => $win->cols,
    );

    $rc->text_at( 2, 2, "Hello, world!", $self->pen );

    $rc->render_to_window( $win );
 }

=head1 DESCRIPTION

Provides a buffer of pending rendering operations to apply to a Window. The
buffer is modified by rendering operations performed by the widget, and
flushed to the widget's window when complete.

This provides the following advantages:

=over 2

=item *

Changes can be made in any order, and will be flushed in top-to-bottom,
left-to-right order, minimising cursor movements.

=item *

Buffered content can be overwritten or partly erased once stored, simplifying
some styles of drawing operation.

=item *

The buffer supports line-drawing, complete with merging of line segments that
meet in a character cell.

=back

This code is still in the experiment stage. At some future point it may be
merged into the main L<Tickit> distribution, and reimplemented in efficient XS
or C code.

=cut

use Struct::Dumb;
struct Cell => [qw(   state  len    penidx textidx textoffs linemask )];
sub SkipCell  { Cell( SKIP,  $_[0], 0,     0,      undef,   undef    ) }
sub TextCell  { Cell( TEXT,  $_[0], $_[1], $_[2],  $_[3],   undef    ) }
sub EraseCell { Cell( ERASE, $_[0], $_[1], 0,      undef,   undef    ) }
sub ContCell  { Cell( CONT,  $_[0], 0,     0,      undef,   undef    ) }
sub LineCell  { Cell( LINE,  1,     $_[1], 0,      undef,   $_[0]    ) }

=head1 CONSTRUCTOR

=cut

=head2 $rc = Tickit::RenderContext->new( %args )

Returns a new instance of a C<Tickit::RenderContext>.

Takes the following named arguments:

=over 8

=item lines => INT

=item cols => INT

The size of the buffer area.

=back

=cut

sub new
{
   my $class = shift;
   my %args = @_;

   my $self = bless {
      lines => my $lines = $args{lines},
      cols  => my $cols  = $args{cols},
      pens  => [],
      texts => [],
   }, $class;

   $self->reset;

   return $self;
}

=head1 METHODS

=cut

=head2 $lines = $rc->lines

=head2 $cols = $rc->cols

Returns the size of the buffer area

=cut

sub lines { shift->{lines} }
sub cols  { shift->{cols} }

=head2 $rc->reset

Removes any pending changes and reverts the render context to its default
empty state.

=cut

sub reset
{
   my $self = shift;

   $self->{cells} = [ map {
      [ SkipCell( $self->cols ), map { ContCell( 0 ) } 1 .. $self->cols-1 ]
   } 1 .. $self->lines ];

   $self->{pens} = [];
   $self->{texts} = [];
}

sub _empty_span
{
   my $self = shift;
   my ( $line, $col, $len ) = @_;

   my $cells = $self->{cells};

   my $spanstart;
   if( $cells->[$line][$col]->state == CONT ) {
      $spanstart = $cells->[$line][$col]->len; # column
   }
   else {
      $spanstart = $col;
   }

   my $spancell  = $cells->[$line][$spanstart];
   my $spanstate = $spancell->state;
   my $spanend   = $spanstart + $spancell->len;

   my $end = $col + $len;

   if( $end < $spanend ) {
      my $afterlen = $spanend - $end;
      given( $spanstate ) {
         when( SKIP ) {
            $cells->[$line][$end] = SkipCell( $afterlen );
         }
         when( TEXT ) {
            # TODO: This doens't handle doublewidth
            string_count( $self->{texts}[$spancell->textidx],
                          my $startpos = Tickit::StringPos->zero,
                          Tickit::StringPos->limit_columns( $end - $spanstart ) );
            $cells->[$line][$end] = TextCell( $afterlen, $spancell->penidx, $spancell->textidx, $startpos->columns );
         }
         when( ERASE ) {
            $cells->[$line][$end] = EraseCell( $afterlen, $spancell->penidx );
         }
         default {
            die "TODO: split _empty_span after in state $spanstate";
         }
      }
      # We know all these are already CONT cells
      $cells->[$line][$_]->len = $end for $end+1 .. $spanend-1;
   }

   if( $col > $spanstart ) {
      my $beforelen = $col - $spanstart;
      given( $spanstate ) {
         when( [SKIP, TEXT, ERASE] ) {
            $cells->[$line][$spanstart]->len = $beforelen;
         }
         default {
            die "TODO: split _empty_span before in state $spanstate";
         }
      }
   }
}

sub _push_pen
{
   my $self = shift;
   my ( $pen ) = @_;

   $self->{pens}[$_] == $pen and return $_ for 0 .. $#{ $self->{pens} };

   push @{ $self->{pens} }, $pen;
   return $#{ $self->{pens} };
}

# Methods to alter cell states

=head2 $rc->clear( $pen )

A shortcut to calling C<erase_at> for every line.

=cut

sub clear
{
   my $self = shift;
   my ( $pen ) = @_;

   # Since we're about to kill all the content, we should empty the text and
   # pen buffers first
   undef @{ $self->{pens} };
   undef @{ $self->{texts} };

   foreach my $line ( 0 .. $self->lines - 1 ) {
      $self->erase_at( $line, 0, $self->cols, $pen );
   }
}

=head2 $rc->skip_at( $line, $col, $len )

Sets the range of cells given to a skipped state. No content will be drawn
here, nor will any content existing on the window be erased.

Initially, or after calling C<reset>, all cells are set to this state.

=cut

sub skip_at
{
   my $self = shift;
   my ( $line, $col, $len ) = @_;

   return if $line < 0 or $line >= $self->lines or $col >= $self->cols;
   $len += $col, $col = 0 if $col < 0;
   return if $len <= 0;
   $len = $self->cols - $col if $len > $self->cols - $col;

   my $cells = $self->{cells};

   $self->_empty_span( $line, $col, $len );

   $cells->[$line][$col] = SkipCell( $len );
   $cells->[$line][$_]   = ContCell( $col ) for $col+1 .. $col+$len-1;
}

=head2 $rc->text_at( $line, $col, $text, $pen )

Sets the range of cells starting at the given position, to render the given
text in the given pen.

=cut

sub text_at
{
   my $self = shift;
   my ( $line, $col, $text, $pen ) = @_;

   return if $line < 0 or $line >= $self->lines or $col >= $self->cols;

   my $len = textwidth( $text );

   my $startcol = 0;
   $len += $col, $startcol -= $col, $col = 0 if $col < 0;
   return if $len <= 0;
   $len = $self->cols - $col if $len > $self->cols - $col;

   my $cells = $self->{cells};

   $self->_empty_span( $line, $col, $len );

   push @{ $self->{texts} }, $text;
   my $textidx = $#{$self->{texts}};

   my $penidx = $self->_push_pen( $pen );

   $cells->[$line][$col] = TextCell( $len, $penidx, $textidx, $startcol );
   $cells->[$line][$_]   = ContCell( $col ) for $col+1 .. $col+$len-1;
}

=head2 $rc->erase_at( $line, $col, $len, $pen )

Sets the range of cells given to erase with the given pen.

=cut

sub erase_at
{
   my $self = shift;
   my ( $line, $col, $len, $pen ) = @_;

   return if $line < 0 or $line >= $self->lines or $col >= $self->cols;
   $len += $col, $col = 0 if $col < 0;
   return if $len <= 0;
   $len = $self->cols - $col if $len > $self->cols - $col;

   my $cells = $self->{cells};

   $self->_empty_span( $line, $col, $len );

   my $penidx = $self->_push_pen( $pen );

   $cells->[$line][$col] = EraseCell( $len, $penidx );
   $cells->[$line][$_]   = ContCell( $col ) for $col+1 .. $col+$len-1;
}

# Line drawing
# Various parts of this code borrowed from Tom Molesworth's Tickit::Canvas

# Bitmasks on Cell linemask
use constant {
   # Connections to the next cell upwards
   NORTH        => 0x03,
   NORTH_SINGLE => 0x01,
   NORTH_DOUBLE => 0x02,
   NORTH_THICK  => 0x03,
   NORTH_SHIFT  => 0,

   # Connections to the next cell to the right
   EAST         => 0x0C,
   EAST_SINGLE  => 0x04,
   EAST_DOUBLE  => 0x08,
   EAST_THICK   => 0x0C,
   EAST_SHIFT   => 2,

   # Connections to the next cell downwards
   SOUTH        => 0x30,
   SOUTH_SINGLE => 0x10,
   SOUTH_DOUBLE => 0x20,
   SOUTH_THICK  => 0x30,
   SOUTH_SHIFT  => 4,

   # Connections to the next cell to the left
   WEST         => 0xC0,
   WEST_SINGLE  => 0x40,
   WEST_DOUBLE  => 0x80,
   WEST_THICK   => 0xC0,
   WEST_SHIFT   => 6,
};

my @linechars;
{
   my $char;
   while( <DATA> ) {
      chomp;
      my $spec;
      if( m/=>/ ) {
         ( $char, $spec ) = split( m/\s+=>\s+/, $_, 2 );
      }
      else {
         $spec = $_;
      }

      my $mask = 0;
      $mask |= __PACKAGE__->$_ for $spec =~ m/([A-Z_]+)/g;

      $linechars[$mask] = $char;
   }
}

sub linecell
{
   my $self = shift;
   my ( $line, $col, $bits, $pen ) = @_;

   return if $line < 0 or $line >= $self->lines or $col < 0 or $col >= $self->cols;

   my $penidx = $self->_push_pen( $pen );

   my $cell = $self->{cells}[$line][$col];
   if( $cell->state != LINE ) {
      $self->_empty_span( $line, $col, 1 );
      $cell = $self->{cells}[$line][$col] = LineCell( 0, $penidx );
   }

   if( $cell->penidx != $penidx ) {
      warn "Pen collision for line cell ($line,$col)\n";
      $cell->linemask = 0;
      $cell->penidx = $penidx;
   }

   $cell->linemask |= $bits;
}

=head2 $rc->hline( $line, $startcol, $endcol, $style, $pen )

Draws a horizontal line between the given columns (both are inclusive), in the
given line style, with the given pen.

C<$style> should be one of three exported constants:

=over 4

=item * LINE_SINGLE

A single, thin line

=item * LINE_DOUBLE

A pair of double, thin lines

=item * LINE_THICK

A single, thick line

=back

=cut

sub hline
{
   my $self = shift;
   my ( $line, $startcol, $endcol, $style, $pen ) = @_;

   # TODO: _empty_span first for efficiency

   $self->linecell( $line, $startcol, $style << EAST_SHIFT, $pen );
   foreach my $col ( $startcol+1 .. $endcol-1 ) {
      $self->linecell( $line, $col, $style << EAST_SHIFT | $style << WEST_SHIFT, $pen );
   }
   $self->linecell( $line, $endcol, $style << WEST_SHIFT, $pen );
}

=head2 $rc->vline( $startline, $endline, $col, $style, $pen )

Draws a vertical line between the given lines (both are inclusive), in the
given line style, with the given pen. C<$style> is as for C<hline>.

=cut

sub vline
{
   my $self = shift;
   my ( $startline, $endline, $col, $style, $pen ) = @_;

   $self->linecell( $startline, $col, $style << SOUTH_SHIFT, $pen );
   foreach my $line ( $startline+1 .. $endline-1 ) {
      $self->linecell( $line, $col, $style << NORTH_SHIFT | $style << SOUTH_SHIFT, $pen );
   }
   $self->linecell( $endline, $col, $style << NORTH_SHIFT, $pen );
}

=head2 $rc->render_to_window( $win )

Renders the stored content to the given L<Tickit::Window>. After this, the
context will be cleared and reset back to initial state.

=cut

sub render_to_window
{
   my $self = shift;
   my ( $win ) = @_;

   my $cells = $self->{cells};

   foreach my $line ( 0 .. $self->lines-1 ) {
      my $phycol;

      for ( my $col = 0; $col < $self->cols ; ) {
         my $cell = $cells->[$line][$col];

         $col += $cell->len, next if $cell->state == SKIP;

         if( !defined $phycol or $phycol < $col ) {
            $win->goto( $line, $col );
         }
         $phycol = $col;

         given( $cell->state ) {
            when( TEXT ) {
               my $text = $self->{texts}[$cell->textidx];
               my $pen  = $self->{pens}[$cell->penidx];
               $phycol += $win->print( substrwidth( $text, $cell->textoffs, $cell->len ), $pen )->columns;
            }
            when( ERASE ) {
               my $pen = $self->{pens}[$cell->penidx];
               if( $col + $cell->len < $self->cols ) {
                  $phycol += $win->erase( $cell->len, $pen, 1 )->columns;
               }
               else {
                  $win->erase( $cell->len, $pen );
                  undef $phycol;
               }
            }
            when( LINE ) {
               my $pen = $self->{pens}[$cell->penidx];
               my $linemask = $cell->linemask;
               my $char = $linechars[$linemask];
               if( defined $char ) {
                  $phycol += $win->print( $char, $pen )->columns;
               }
               else {
                  printf STDERR "TODO: pen linemask %02x\n", $linemask;
               }
            }
            default {
               die "TODO: cell in state ". $cell->state;
            }
         }

         $col += $cell->len;
      }
   }

   $self->reset;
}

=head1 TODO

As this code is still experimental, there are many planned features it
currently lacks:

=over 2

=item *

A C<char_at> method to store a single Unicode character more effiicently than
a 1-column text cell. This may be useful for drawing characters such as arrows
and tick-marks.

=item *

A virtual cursor position and pen state, to allow drawing in a
position-relative rather than absolute style.

=item *

Clipping rectangle to support partial window updates

=item *

Hole regions, to directly support shadows made by floating windows

=item *

Child contexts, to support cascading render/expose logic down a window tree

=item *

Direct rendering to a L<Tickit::Term> instead of a Window.

=back

=cut

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>

=cut

0x55AA;

use utf8;
__DATA__
─ => WEST_SINGLE | EAST_SINGLE
━ => WEST_THICK | EAST_THICK
│ => NORTH_SINGLE | SOUTH_SINGLE
┃ => NORTH_THICK | SOUTH_THICK
┌ => SOUTH_SINGLE | EAST_SINGLE
┍ => SOUTH_SINGLE | EAST_THICK
┎ => SOUTH_THICK | EAST_SINGLE
┏ => SOUTH_THICK | EAST_THICK
┐ => SOUTH_SINGLE | WEST_SINGLE
┑ => SOUTH_SINGLE | WEST_THICK
┒ => SOUTH_THICK | WEST_SINGLE
┓ => SOUTH_THICK | WEST_THICK
└ => NORTH_SINGLE | EAST_SINGLE
┕ => NORTH_SINGLE | EAST_THICK
┖ => NORTH_THICK | EAST_SINGLE
┗ => NORTH_THICK | EAST_THICK
┘ => NORTH_SINGLE | WEST_SINGLE
┙ => NORTH_SINGLE | WEST_THICK
┚ => NORTH_THICK | WEST_SINGLE
┛ => NORTH_THICK | WEST_THICK
├ => NORTH_SINGLE | EAST_SINGLE | SOUTH_SINGLE
┝ => NORTH_SINGLE | SOUTH_SINGLE | EAST_THICK
┞ => NORTH_THICK | EAST_SINGLE | SOUTH_SINGLE
┟ => NORTH_SINGLE | EAST_SINGLE | SOUTH_THICK
┠ => NORTH_THICK | EAST_SINGLE | SOUTH_THICK
┡ => NORTH_THICK | EAST_THICK | SOUTH_SINGLE
┢ => NORTH_SINGLE | EAST_THICK | SOUTH_THICK
┣ => NORTH_THICK | EAST_THICK | SOUTH_THICK
┤ => NORTH_SINGLE | WEST_SINGLE | SOUTH_SINGLE
┥ => NORTH_SINGLE | SOUTH_SINGLE | WEST_THICK
┦ => WEST_SINGLE | NORTH_THICK | SOUTH_SINGLE
┧ => NORTH_SINGLE | WEST_SINGLE | SOUTH_THICK
┨ => WEST_SINGLE | NORTH_THICK | SOUTH_THICK
┩ => WEST_THICK | NORTH_THICK | SOUTH_SINGLE
┪ => WEST_THICK | NORTH_SINGLE | SOUTH_THICK
┫ => WEST_THICK | NORTH_THICK | SOUTH_THICK
┬ => WEST_SINGLE | SOUTH_SINGLE | EAST_SINGLE
┭ => WEST_THICK | SOUTH_SINGLE | EAST_SINGLE
┮ => WEST_SINGLE | SOUTH_SINGLE | EAST_THICK
┯ => WEST_THICK | SOUTH_SINGLE | EAST_THICK
┰ => WEST_SINGLE | SOUTH_THICK | EAST_SINGLE
┱ => WEST_THICK | SOUTH_THICK | EAST_SINGLE
┲ => WEST_SINGLE | SOUTH_THICK | EAST_THICK
┳ => WEST_THICK | SOUTH_THICK | EAST_THICK
┴ => WEST_SINGLE | NORTH_SINGLE | EAST_SINGLE
┵ => WEST_THICK | NORTH_SINGLE | EAST_SINGLE
┶ => WEST_SINGLE | NORTH_SINGLE | EAST_THICK
┷ => WEST_THICK | NORTH_SINGLE | EAST_THICK
┸ => WEST_SINGLE | NORTH_THICK | EAST_SINGLE
┹ => WEST_THICK | NORTH_THICK | EAST_SINGLE
┺ => WEST_SINGLE | NORTH_THICK | EAST_THICK
┻ => WEST_THICK | NORTH_THICK | EAST_THICK
┼ => WEST_SINGLE | NORTH_SINGLE | EAST_SINGLE | SOUTH_SINGLE
┽ => WEST_THICK | NORTH_SINGLE | EAST_SINGLE | SOUTH_SINGLE
┾ => WEST_SINGLE | NORTH_SINGLE | EAST_THICK | SOUTH_SINGLE
┿ => WEST_THICK | NORTH_SINGLE | EAST_THICK | SOUTH_SINGLE
╀ => WEST_SINGLE | NORTH_THICK | EAST_SINGLE | SOUTH_SINGLE
╁ => WEST_SINGLE | NORTH_SINGLE | EAST_SINGLE | SOUTH_THICK
╂ => WEST_SINGLE | NORTH_THICK | EAST_SINGLE | SOUTH_THICK
╃ => WEST_THICK | NORTH_THICK | EAST_SINGLE | SOUTH_SINGLE
╄ => WEST_SINGLE | NORTH_THICK | EAST_THICK | SOUTH_SINGLE
╅ => WEST_THICK | NORTH_SINGLE | EAST_SINGLE | SOUTH_THICK
╆ => WEST_SINGLE | NORTH_SINGLE | EAST_THICK | SOUTH_THICK
╇ => WEST_THICK | NORTH_THICK | EAST_THICK | SOUTH_SINGLE
╈ => WEST_THICK | NORTH_SINGLE | EAST_THICK | SOUTH_THICK
╉ => WEST_THICK | NORTH_THICK | EAST_SINGLE | SOUTH_THICK
╊ => WEST_SINGLE | NORTH_THICK | EAST_THICK | SOUTH_THICK
╋ => WEST_THICK | NORTH_THICK | EAST_THICK | SOUTH_THICK
═ => WEST_DOUBLE | EAST_DOUBLE
║ => NORTH_DOUBLE | SOUTH_DOUBLE
╒ => EAST_DOUBLE | SOUTH_SINGLE
╓ => EAST_SINGLE | SOUTH_DOUBLE
╔ => SOUTH_DOUBLE | EAST_DOUBLE
╕ => WEST_DOUBLE | SOUTH_SINGLE
╖ => WEST_SINGLE | SOUTH_DOUBLE
╗ => WEST_DOUBLE | SOUTH_DOUBLE
╘ => NORTH_SINGLE | EAST_DOUBLE
╙ => NORTH_DOUBLE | EAST_SINGLE
╚ => NORTH_DOUBLE | EAST_DOUBLE
╛ => WEST_DOUBLE | NORTH_SINGLE
╜ => WEST_SINGLE | NORTH_DOUBLE
╝ => WEST_DOUBLE | NORTH_DOUBLE
╞ => NORTH_SINGLE | EAST_DOUBLE | SOUTH_SINGLE
╟ => NORTH_DOUBLE | EAST_SINGLE | SOUTH_DOUBLE
╠ => NORTH_DOUBLE | EAST_DOUBLE | SOUTH_DOUBLE
╡ => WEST_DOUBLE | NORTH_SINGLE | SOUTH_SINGLE
╢ => WEST_SINGLE | NORTH_DOUBLE | SOUTH_DOUBLE
╣ => WEST_DOUBLE | NORTH_DOUBLE | SOUTH_DOUBLE
╤ => WEST_DOUBLE | SOUTH_SINGLE | EAST_DOUBLE
╥ => WEST_SINGLE | SOUTH_DOUBLE | EAST_SINGLE
╦ => WEST_DOUBLE | SOUTH_DOUBLE | EAST_DOUBLE
╧ => WEST_DOUBLE | NORTH_SINGLE | EAST_DOUBLE
╨ => WEST_SINGLE | NORTH_DOUBLE | EAST_SINGLE
╩ => WEST_DOUBLE | NORTH_DOUBLE | EAST_DOUBLE
╪ => WEST_DOUBLE | NORTH_SINGLE | EAST_DOUBLE | SOUTH_SINGLE
     WEST_DOUBLE | NORTH_THICK  | EAST_DOUBLE | SOUTH_THICK
╫ => WEST_SINGLE | NORTH_DOUBLE | EAST_SINGLE | SOUTH_DOUBLE
     WEST_THICK  | NORTH_DOUBLE | EAST_THICK  | SOUTH_DOUBLE
╬ => WEST_DOUBLE | NORTH_DOUBLE | EAST_DOUBLE | SOUTH_DOUBLE
╴ => WEST_SINGLE
╵ => NORTH_SINGLE
╶ => EAST_SINGLE
╷ => SOUTH_SINGLE
╸ => WEST_THICK
╹ => NORTH_THICK
╺ => EAST_THICK
╻ => SOUTH_THICK
╼ => WEST_SINGLE | EAST_THICK
╽ => NORTH_SINGLE | SOUTH_THICK
╾ => WEST_THICK | EAST_SINGLE
╿ => NORTH_THICK | SOUTH_SINGLE
