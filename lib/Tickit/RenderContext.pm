#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2013 -- leonerd@leonerd.org.uk

package Tickit::RenderContext;

use strict;
use warnings;
use feature qw( switch );

our $VERSION = '0.03';

use Carp;
use Scalar::Util qw( refaddr );

use Tickit::Utils qw( textwidth substrwidth string_count );
use Tickit::StringPos;
use Tickit::Rect;
use Tickit::Pen;

# Exported API constants
use Exporter 'import';
our @EXPORT_OK = qw(
   LINE_SINGLE LINE_DOUBLE LINE_THICK
   CAP_START CAP_END CAP_BOTH
);
use constant {
   LINE_SINGLE => 0x01,
   LINE_DOUBLE => 0x02,
   LINE_THICK  => 0x03,
};
use constant {
   CAP_START => 0x01,
   CAP_END   => 0x02,
   CAP_BOTH  => 0x03,
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
    my %args = @_;
    my $win = $self->window or return;

    my $rc = Tickit::RenderContext->new(
       lines => $win->lines,
       cols  => $win->cols,
    );
    $rc->clip( $args{rect} );

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
some styles of drawing operation. Large areas can be erased, and then redrawn
with text or lines, without causing a double-drawing flicker on the output
terminal.

=item *

The buffer supports line-drawing, complete with merging of line segments that
meet in a character cell. Boxes, grids, and other shapes can be easily formed
by drawing separate line segments, and the render context will handle the
corners and other junctions formed.

=back

Drawing methods come in two forms; absolute, and cursor-relative:

=over 2

=item *

Absolute methods, identified by their name having a suffixed C<_at>, operate
on a position within the buffer specified by their argument.

=item *

Cursor-relative methods, identified by their lack of C<_at> suffix, operate at
and update the position of the "virtual cursor". This is a position within the
buffer that can be set using the C<goto> method. The position of the virtual
cursor is not affected by the absolute-position methods.

=back

This code is still in the experiment stage. At some future point it may be
merged into the main L<Tickit> distribution, and reimplemented in efficient XS
or C code. As such, recommendations and best-practices are still subject to
change and evolution as the code progresses.

=head2 State Stack

The render context stores a stack of saved state. The state of the context can
be stored using the C<save> method, so that changes can be made, before
finally restoring back to that state using C<restore>. The following items of
state are saved:

=over 2

=item *

The virtual cursor position

=item *

The clipping rectangle

=item *

The render pen

=item *

The translation offset

=back

When the state is saved to the stack, the render pen is remembered and merged
with any pen set using the C<setpen> method.

The queued content to render is not part of the state stack. It is intended
that the state stack be used to implement recursive delegation of drawing
operations down a tree of code, allowing child contexts to be created by
saving state and modifying it, to later restore it again afterwards.

=cut

use Struct::Dumb;

struct Cell => [qw(   state  len    penidx textidx textoffs linemask )];
sub SkipCell  { Cell( SKIP,  $_[0], 0,     0,      undef,   undef    ) }
sub TextCell  { Cell( TEXT,  $_[0], $_[1], $_[2],  $_[3],   undef    ) }
sub EraseCell { Cell( ERASE, $_[0], $_[1], 0,      undef,   undef    ) }
sub ContCell  { Cell( CONT,  $_[0], 0,     0,      undef,   undef    ) }
sub LineCell  { Cell( LINE,  1,     $_[1], 0,      undef,   $_[0]    ) }

struct State => [qw( line col clip pen xlate_line xlate_col )];
struct StatePen => [qw( pen )];

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

   my $lines = $args{lines};
   my $cols  = $args{cols};

   my $self = bless {
      lines => $lines,
      cols  => $cols,
      pen   => undef,
      xlate_line => 0,
      xlate_col  => 0,
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

sub _xlate_and_clip
{
   my $self = shift;
   my ( $line, $col, $len ) = @_;

   $line += $self->{xlate_line};
   $col  += $self->{xlate_col};

   my $clip = $self->{clip} or return; # undef means totally invisible

   return if $line < $clip->top or
             $line >= $clip->bottom or
             $col >= $clip->right;

   my $startcol = 0;
   if( $col < $clip->left ) {
      $len += $col - $clip->left;
      $startcol -= $col - $clip->left;
      $col = $clip->left;
   }
   return if $len <= 0;

   if( $len > $clip->right - $col ) {
      $len = $clip->right - $col;
   }

   return ( $line, $col, $len, $startcol );
}

=head2 $rc->save

Pushes a new state-saving context to the stack, which can later be returned to
by the C<restore> method.

=cut

sub save
{
   my $self = shift;

   my $savepen = defined $self->{pen} ? Tickit::Pen::Immutable->new( $self->{pen}->getattrs )
                                      : undef;

   push @{ $self->{stack} }, State(
      $self->{line}, $self->{col}, $self->{clip}, $savepen, $self->{xlate_line}, $self->{xlate_col},
   );
}

=head2 $rc->savepen

Pushes a new state-saving context to the stack that only stores the pen. This
can later be returned to by the C<restore> method, but will only restore the
pen. Other attributes such as the virtual cursor position will be unaffected.

=cut

sub savepen
{
   my $self = shift;

   my $savepen = defined $self->{pen} ? Tickit::Pen::Immutable->new( $self->{pen}->getattrs )
                                      : undef;

   push @{ $self->{stack} }, StatePen( $savepen );
}

=head2 $rc->restore

Pops and restores a saved state previously created with C<save>.

=cut

sub restore
{
   my $self = shift;

   my $state = pop @{ $self->{stack} };

   $self->{pen}  = $state->pen;

   if( $state->isa( "Tickit::RenderContext::State" ) ) {
      $self->{line} = $state->line;
      $self->{col}  = $state->col;
      $self->{clip} = $state->clip;
      $self->{xlate_line} = $state->xlate_line;
      $self->{xlate_col}  = $state->xlate_col;
   }
}

=head2 $rc->clip( $rect )

Restricts the clipping rectangle of drawing operations to be no further than
the limits of the given rectangle. This will apply to subsequent rendering
operations but does not affect existing content, nor the actual rendering to
the window.

Clipping rectangles cumulative; each call further restricts the drawing
region. To revert back to a larger drawing area, use the C<save> and
C<restore> stack.

=cut

sub clip
{
   my $self = shift;
   my ( $rect ) = @_;

   # $self->{clip} is always in output coordinates

   $self->{clip} = $self->{clip}->intersect( $rect->translate( $self->{xlate_line}, $self->{xlate_col} ) );

   # There's a chance clip is now undef; but that's OK - that means we're totally invisible
}

=head2 $rc->translate( $downward, $rightward )

Applies a translation to the coordinate system used by C<goto> and the
absolute-position methods C<*_at>. After this call, all positions used will be
offset by the given amount.

=cut

sub translate
{
   my $self = shift;
   my ( $downward, $rightward ) = @_;

   $self->{xlate_line} += $downward;
   $self->{xlate_col}  += $rightward;
}

=head2 $rc->reset

Removes any pending changes and reverts the render context to its default
empty state. Undefines the virtual cursor position, resets the clipping
rectangle, and clears the stack of saved state.

=cut

sub reset
{
   my $self = shift;

   $self->{cells} = [ map {
      [ SkipCell( $self->cols ), map { ContCell( 0 ) } 1 .. $self->cols-1 ]
   } 1 .. $self->lines ];

   $self->{pens} = [];
   $self->{texts} = [];

   $self->{stack} = [];

   undef $self->{line};
   undef $self->{col};

   $self->{clip} = Tickit::Rect->new(
      top => 0, left => 0, lines => $self->lines, cols => $self->cols,
   );
}

sub _make_span
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
            die "TODO: split _make_span after in state $spanstate";
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
            die "TODO: split _make_span before in state $spanstate";
         }
      }
   }

   $cells->[$line][$_]   = ContCell( $col ) for $col+1 .. $col+$len-1;

   return $cells->[$line][$col];
}

sub _push_pen
{
   my $self = shift;
   my ( $pen ) = @_;

   defined $pen and $pen->isa( "Tickit::Pen" ) or croak "Expected a pen";

   # TODO: currently just care about object identity, but maybe we want to
   # merge equivalent pens too?
   my $penaddr = refaddr($pen);
   refaddr($self->{pens}[$_]) == $penaddr and return $_ for 0 .. $#{ $self->{pens} };

   push @{ $self->{pens} }, $pen;
   return $#{ $self->{pens} };
}

# Methods to alter cell states

=head2 $rc->clear( $pen )

Resets every cell in the buffer to an erased state. 
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

=head2 $rc->goto( $line, $col )

Sets the position of the virtual cursor.

=cut

sub goto
{
   my $self = shift;
   @{$self}{qw( line col )} = @_;
}

=head2 $rc->setpen( $pen )

Sets the rendering pen to use for C<text> and C<erase> operations. If a pen is
set then a C<$pen> argument should no longer be supplied to the C<text> or
C<erase> methods.

Successive calls to this method will replace the active pen used, but if there
is a saved state on the stack it will be merged with the rendering pen of the
most recent saved state.

=cut

sub setpen
{
   my $self = shift;
   my ( $pen ) = @_;

   if( @{ $self->{stack} } and defined( my $prevpen = $self->{stack}[-1]->pen ) ) {
      $self->{pen} = Tickit::Pen::Immutable->new( $prevpen->getattrs, $pen->getattrs );
   }
   elsif( defined $pen ) {
      $self->{pen} = Tickit::Pen::Immutable->new( $pen->getattrs );
   }
   else {
      undef $self->{pen};
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
   ( $line, $col, $len ) = $self->_xlate_and_clip( $line, $col, $len ) or return;

   my $cell = $self->_make_span( $line, $col, $len );

   $cell->state = SKIP;
   $cell->len   = $len;
}

=head2 $rc->skip( $len )

Sets the range of cells at the virtual cursor position to a skipped state, and
updates the position.

=cut

sub skip
{
   my $self = shift;
   my ( $len ) = @_;
   defined $self->{line} or croak "Cannot ->skip without a virtual cursor position";
   $self->skip_at( $self->{line}, $self->{col}, $len );
   $self->{col} += $len;
}

=head2 $rc->skip_to( $col )

Sets the range of cells from the virtual cursor position until before the
given column to a skipped state, and updates the position to the column.

If the position is already past this column then the cursor is moved backwards
and no buffer changes are made.

=cut

sub skip_to
{
   my $self = shift;
   my ( $col ) = @_;
   defined $self->{line} or croak "Cannot ->skip_to without a virtual cursor position";

   if( $self->{col} < $col ) {
      $self->skip_at( $self->{line}, $self->{col}, $col - $self->{col} );
   }

   $self->{col} = $col;
}

sub _text_at
{
   my $self = shift;
   my ( $line, $col, $text, $len, $pen ) = @_;
   ( $line, $col, $len, my $startcol ) = $self->_xlate_and_clip( $line, $col, $len ) or return;

   push @{ $self->{texts} }, $text;
   my $textidx = $#{$self->{texts}};

   my $cell = $self->_make_span( $line, $col, $len );

   $cell->state    = TEXT;
   $cell->len      = $len;
   $cell->penidx   = $self->_push_pen( $pen );
   $cell->textidx  = $textidx;
   $cell->textoffs = $startcol;
}

=head2 $rc->text_at( $line, $col, $text, $pen )

Sets the range of cells starting at the given position, to render the given
text in the given pen.

=cut

sub text_at
{
   my $self = shift;
   my ( $line, $col, $text, $pen ) = @_;
   $self->_text_at( $line, $col, $text, textwidth( $text ), $pen );
}

=head2 $rc->text( $text, $pen )

Sets the range of cells at the virtual cursor position to render the given
text in the given pen, and updates the position.

=cut

sub text
{
   my $self = shift;
   my ( $text, $pen ) = @_;
   defined $self->{line} or croak "Cannot ->text without a virtual cursor position";
   $pen and $self->{pen} and croak "Cannot ->text with both a pen and implied pen";
   $pen ||= $self->{pen};
   my $len = textwidth( $text );
   $self->_text_at( $self->{line}, $self->{col}, $text, $len, $pen );
   $self->{col} += $len;
}

=head2 $rc->erase_at( $line, $col, $len, $pen )

Sets the range of cells given to erase with the given pen.

=cut

sub erase_at
{
   my $self = shift;
   my ( $line, $col, $len, $pen ) = @_;
   ( $line, $col, $len ) = $self->_xlate_and_clip( $line, $col, $len ) or return;

   my $cell = $self->_make_span( $line, $col, $len );

   $cell->state  = ERASE;
   $cell->len    = $len;
   $cell->penidx = $self->_push_pen( $pen );
}

=head2 $rc->erase( $len, $pen )

Sets the range of cells at the virtual cursor position to erase with the given
pen, and updates the position.

=cut

sub erase
{
   my $self = shift;
   my ( $len, $pen ) = @_;
   defined $self->{line} or croak "Cannot ->erase without a virtual cursor position";
   $pen and $self->{pen} and croak "Cannot ->erase with both a pen and implied pen";
   $pen ||= $self->{pen};
   $self->erase_at( $self->{line}, $self->{col}, $len, $pen );
   $self->{col} += $len;
}

=head2 $rc->erase_to( $col, $pen )

Sets the range of cells from the virtual cursor position until before the
given column to erase with the given pen, and updates the position to the
column.

If the position is already past this column then the cursor is moved backwards
and no buffer changes are made.

=cut

sub erase_to
{
   my $self = shift;
   my ( $col, $pen ) = @_;
   defined $self->{line} or croak "Cannot ->erase_to without a virtual cursor position";
   $pen and $self->{pen} and croak "Cannot ->erase_to with both a pen and implied pen";
   $pen ||= $self->{pen};

   if( $self->{col} < $col ) {
      $self->erase_at( $self->{line}, $self->{col}, $col - $self->{col}, $pen );
   }

   $self->{col} = $col;
}

=head1 LINE DRAWING

The render context buffer supports storing line-drawing characters in cells,
and can merge line segments where they meet, attempting to draw the correct
character for the segments that meet in each cell.

There are three exported constants giving supported styles of line drawing:

=over 4

=item * LINE_SINGLE

A single, thin line

=item * LINE_DOUBLE

A pair of double, thin lines

=item * LINE_THICK

A single, thick line

=back

Note that linedrawing is performed by Unicode characters, and not every
possible combination of line segments of differing styles meeting in a cell is
supported by Unicode. The following sets of styles may be relied upon:

=over 4

=item *

Any possible combination of only C<SINGLE> segments, C<THICK> segments, or
both.

=item *

Any combination of only C<DOUBLE> segments, except cells that only have one of
the four borders occupied.

=item *

Any combination of C<SINGLE> and C<DOUBLE> segments except where the style
changes between C<SINGLE> to C<DOUBLE> on a vertical or horizontal run.

=back

Other combinations are not directly supported (i.e. any combination of
C<DOUBLE> and C<THICK> in the same cell, or any attempt to change from
C<SINGLE> to C<DOUBLE> in either the vertical or horizontal direction). To
handle these cases, a cell may be rendered with a substitution character which
replaces a C<DOUBLE> or C<THICK> segment with a C<SINGLE> one within that
cell. The effect will be the overall shape of the line is retained, but close
to the edge or corner it will have the wrong segment type.

Conceptually, every cell involved in line drawing has a potential line segment
type at each of its four borders to its neighbours. Horizontal lines are drawn
though the vertical centre of each cell, and vertical lines are drawn through
the horizontal centre.

There is a choice of how to handle the ends of line segments, as to whether
the segment should go to the centre of each cell, or should continue through
the entire body of the cell and stop at the boundary. By default line segments
will start and end at the centre of the cells, so that horizontal and vertical
lines meeting in a cell will form a neat corner. When drawing isolated lines
such as horizontal or vertical rules, it is preferrable that the line go right
through the cells at the start and end. To control this behaviour, the
C<$caps> bitmask is used. C<CAP_START> and C<CAP_END> state that the line
should consume the whole of the start or end cell, respectively; C<CAP_BOTH>
is a convenient shortcut specifying both behaviours.

A rectangle may be formed by combining two C<hline_at> and two C<vline_at>
calls, without end caps:

 $rc->hline_at( $top,    $left, $right, $style, $pen );
 $rc->hline_at( $bottom, $left, $right, $style, $pen );
 $rc->vline_at( $top, $bottom, $left,  $style, $pen );
 $rc->vline_at( $top, $bottom, $right, $style, $pen );

=cut

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
   while( <DATA> ) {
      chomp;
      my ( $char, $spec ) = split( m/\s+=>\s+/, $_, 2 );

      my $mask = 0;
      $mask |= __PACKAGE__->$_ for $spec =~ m/([A-Z_]+)/g;

      $linechars[$mask] = $char;
   }

   close DATA;

   # Fill in the gaps
   foreach my $mask ( 1 .. 255 ) {
      next if defined $linechars[$mask];

      # Try with SINGLE instead of THICK, so mask away 0xAA
      if( my $char = $linechars[$mask & 0xAA] ) {
         $linechars[$mask] = $char;
         next;
      }

      # The only ones left now are awkward mixes of single/double
      # Turn DOUBLE into SINGLE
      my $singlemask = $mask;
      foreach my $dir (qw( NORTH EAST SOUTH WEST )) {
         my $dirmask = __PACKAGE__->$dir;
         my $dirshift = __PACKAGE__->${\"${dir}_SHIFT"};

         my $dirsingle = LINE_SINGLE << $dirshift;
         my $dirdouble = LINE_DOUBLE << $dirshift;

         $singlemask = ( $singlemask & ~$dirmask ) | $dirsingle
            if ( $singlemask & $dirmask ) == $dirdouble;
      }

      if( my $char = $linechars[$singlemask] ) {
         $linechars[$mask] = $char;
         next;
      }

      die sprintf "TODO: Couldn't find a linechar for %02x\n", $mask;
   }
}

sub linecell
{
   my $self = shift;
   my ( $line, $col, $bits, $pen ) = @_;
   ( $line, $col ) = $self->_xlate_and_clip( $line, $col, 1 ) or return;

   my $penidx = $self->_push_pen( $pen );

   my $cell = $self->{cells}[$line][$col];
   if( $cell->state != LINE ) {
      $self->_make_span( $line, $col, 1 );
      $cell->state  = LINE;
      $cell->len    = 1;
      $cell->penidx = $penidx;
   }

   if( $cell->penidx != $penidx ) {
      warn "Pen collision for line cell ($line,$col)\n";
      $cell->linemask = 0;
      $cell->penidx = $penidx;
   }

   $cell->linemask |= $bits;
}

=head2 $rc->hline_at( $line, $startcol, $endcol, $style, $pen, $caps )

Draws a horizontal line between the given columns (both are inclusive), in the
given line style, with the given pen.

=cut

sub hline_at
{
   my $self = shift;
   my ( $line, $startcol, $endcol, $style, $pen, $caps ) = @_;
   $caps ||= 0;

   # TODO: _make_span first for efficiency
   my $east = $style << EAST_SHIFT;
   my $west = $style << WEST_SHIFT;

   $self->linecell( $line, $startcol, $east | ($caps & CAP_START ? $west : 0), $pen );
   foreach my $col ( $startcol+1 .. $endcol-1 ) {
      $self->linecell( $line, $col, $east | $west, $pen );
   }
   $self->linecell( $line, $endcol, $west | ($caps & CAP_END ? $east : 0), $pen );
}

=head2 $rc->vline_at( $startline, $endline, $col, $style, $pen, $caps )

Draws a vertical line between the centres of the given lines (both are
inclusive), in the given line style, with the given pen.

=cut

sub vline_at
{
   my $self = shift;
   my ( $startline, $endline, $col, $style, $pen, $caps ) = @_;
   $caps ||= 0;

   my $south = $style << SOUTH_SHIFT;
   my $north = $style << NORTH_SHIFT;

   $self->linecell( $startline, $col, $south | ($caps & CAP_START ? $north : 0), $pen );
   foreach my $line ( $startline+1 .. $endline-1 ) {
      $self->linecell( $line, $col, $north | $south, $pen );
   }
   $self->linecell( $endline, $col, $north | ($caps & CAP_END ? $south : 0), $pen );
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
               # No need to set moveend=true to erasech unless we actually
               # have more content;
               my $moveend = $col + $cell->len < $self->cols &&
                             $cells->[$line][$col + $cell->len]->state != SKIP;

               $phycol += $win->erasech( $cell->len, $moveend || undef, $pen )->columns;
               undef $phycol unless $moveend;
            }
            when( LINE ) {
               # This is more efficient and works better with unit testing in
               # the Perl case but in the C version this is easier just done a
               # cell at a time
               my $penidx = $cell->penidx;
               my $chars = "";
               while( $col < $self->cols and
                      $cell = $cells->[$line][$col] and
                      $cell->state == LINE and
                      $cell->penidx == $penidx ) {
                  $chars .= $linechars[$cell->linemask];
                  $col++;
               }

               my $pen = $self->{pens}[$penidx];
               $phycol += $win->print( $chars, $pen )->columns;

               next;
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

Hole regions, to directly support shadows made by floating windows.

=item *

Child contexts, to support cascading render/expose logic down a window tree.

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
╫ => WEST_SINGLE | NORTH_DOUBLE | EAST_SINGLE | SOUTH_DOUBLE
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
