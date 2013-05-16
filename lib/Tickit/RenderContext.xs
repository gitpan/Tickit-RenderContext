/*  You may distribute under the terms of either the GNU General Public License
 *  or the Artistic License (the same terms as Perl itself)
 *
 *  (C) Paul Evans, 2011-2013 -- leonerd@leonerd.org.uk
 */


#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

/* must match .pm file */
enum TickitRenderContextCellState {
  SKIP  = 0,
  TEXT  = 1,
  ERASE = 2,
  CONT  = 3,
  LINE  = 4,
  CHAR  = 5,
};

typedef struct {
  enum TickitRenderContextCellState state;
  union {
    int len;      // state != CONT
    int startcol; // state == CONT
  };
  SV *pen;        // state -> {TEXT, ERASE, LINE, CHAR}
  union {
    struct { int idx; int offs; } text; // state == TEXT
    struct { int mask;          } line; // state == LINE
    struct { int codepoint;     } chr;  // state == CHAR
  };
} TickitRenderContextCell;

static void cont_cell(TickitRenderContextCell *cell, int startcol)
{
  switch(cell->state) {
    case TEXT:
    case ERASE:
    case LINE:
    case CHAR:
      if(!cell->pen)
        croak("Expected cell in state %d to have a pen but it does not", cell->state);
      SvREFCNT_dec(cell->pen);
      break;
  }

  cell->state    = CONT;
  cell->startcol = startcol;
  cell->pen      = NULL;
}

MODULE = Tickit::RenderContext    PACKAGE = Tickit::RenderContext

void
_xs_new(self)
  HV *self
  INIT:
    int lines, cols;
    TickitRenderContextCell **cells;
    int line, col;
  CODE:
    lines = SvIV(*hv_fetchs(self, "lines", 0));
    cols  = SvIV(*hv_fetchs(self, "cols",  0));

    Newx(cells, lines, TickitRenderContextCell *);
    for(line = 0; line < lines; line++) {
      Newx(cells[line], cols, TickitRenderContextCell);
      for(col = 0; col < cols; col++) {
        cells[line][col].state = CONT;
        cells[line][col].pen = NULL;
      }
    }

    sv_setiv(*hv_fetchs(self, "_xs_cells", 1), (IV)cells);

void
_xs_destroy(self)
  HV *self
  INIT:
    int lines, cols;
    SV *cellsv;
    TickitRenderContextCell **cells;
    int line, col;
  CODE:
    lines = SvIV(*hv_fetchs(self, "lines", 0));
    cols  = SvIV(*hv_fetchs(self, "cols", 0));
    cells = (void *)SvIV(cellsv = *hv_fetchs(self, "_xs_cells", 0));

    for(line = 0; line < lines; line++) {
      for(col = 0; col < cols; col++) {
        TickitRenderContextCell *cell = &cells[line][col];
        switch(cell->state) {
          case TEXT:
          case ERASE:
          case LINE:
          case CHAR:
            SvREFCNT_dec(cell->pen);
            break;
        }
      }
      Safefree(cells[line]);
    }

    Safefree(cells);
    sv_setsv(cellsv, &PL_sv_undef);

void
_xs_reset(self)
  HV *self
  INIT:
    int lines, cols, line, col;
    TickitRenderContextCell **cells;
  CODE:
    lines = SvIV(*hv_fetchs(self, "lines", 0));
    cols  = SvIV(*hv_fetchs(self, "cols",  0));
    cells = (void *)SvIV(*hv_fetchs(self, "_xs_cells", 0));

    for(line = 0; line < lines; line++) {
      // cont_cell also frees pen
      for(col = 0; col < cols; col++)
        cont_cell(&cells[line][col], 0);

      cells[line][0].state = SKIP;
      cells[line][0].len   = cols;
    }

SV *
_xs_getcell(self,line,col)
  HV *self
  int line
  int col
  INIT:
    TickitRenderContextCell **cells;
  CODE:
    if(line < 0 || line >= SvIV(*hv_fetchs(self, "lines", 0)))
      croak("$line out of range");
    if(col < 0 || col >= SvIV(*hv_fetchs(self, "cols", 0)))
      croak("$col out of range");

    cells = (void *)SvIV(*hv_fetchs(self, "_xs_cells", 0));

    RETVAL = newSV(0);
    sv_setref_iv(RETVAL, "Tickit::RenderContext::Cell", (IV)(&cells[line][col]));
  OUTPUT:
    RETVAL

SV *
_xs_make_span(self,line,col,len)
  HV *self
  int line
  int col
  int len
  INIT:
    TickitRenderContextCell **cells;
    int cols;
    int end = col + len;
    int c;
  CODE:
    if(line < 0 || line >= SvIV(*hv_fetchs(self, "lines", 0)))
      croak("$line out of range");
    if(col < 0)
      croak("$col out of range");
    if(len < 1)
      croak("$len out of range");
    if(col + len > (cols = SvIV(*hv_fetchs(self, "cols", 0))))
      croak("$col+$len out of range");

    cells = (void *)SvIV(*hv_fetchs(self, "_xs_cells", 0));

    // If the following cell is a CONT, it needs to become a new start
    if(end < cols && cells[line][end].state == CONT) {
      int spanstart = cells[line][end].startcol;
      TickitRenderContextCell *spancell = &cells[line][spanstart];
      int spanend = spanstart + spancell->len;
      int afterlen = spanend - end;
      TickitRenderContextCell *endcell = &cells[line][end];

      switch(spancell->state) {
        case SKIP:
          endcell->state = SKIP;
          endcell->len   = afterlen;
          break;
        case TEXT:
          endcell->state     = TEXT;
          endcell->len       = afterlen;
          endcell->pen       = newSVsv(spancell->pen);
          endcell->text.idx  = spancell->text.idx;
          endcell->text.offs = spancell->text.offs + end - spanstart;
          break;
        case ERASE:
          endcell->state = ERASE;
          endcell->len   = afterlen;
          endcell->pen   = newSVsv(spancell->pen);
          break;
        default:
          croak("TODO: split _make_span after in state %d", spancell->state);
          return;
      }

      // We know these are already CONT cells
      for(c = end + 1; c < spanend; c++)
        cells[line][c].startcol = end;
    }

    // If the initial cell is a CONT, shorten its start
    if(cells[line][col].state == CONT) {
      int beforestart = cells[line][col].startcol;
      TickitRenderContextCell *spancell = &cells[line][beforestart];
      int beforelen = col - beforestart;

      switch(spancell->state) {
        case SKIP:
        case TEXT:
        case ERASE:
          spancell->len = beforelen;
          break;
        default:
          croak("TODO: split _make_span before in state %d", spancell->state);
          return;
      }
    }

    // cont_cell() also frees any pens in the range
    for(c = col; c < end; c++)
      cont_cell(&cells[line][c], col);

    cells[line][col].len = len;

    RETVAL = newSV(0);
    sv_setref_iv(RETVAL, "Tickit::RenderContext::Cell", (IV)(&cells[line][col]));
  OUTPUT:
    RETVAL

MODULE = Tickit::RenderContext    PACKAGE = Tickit::RenderContext::Cell

int
state(self)
  SV *self
  INIT:
    TickitRenderContextCell *cell;
  CODE:
    cell = (void *)SvIV(SvRV(self));
    RETVAL = cell->state;
  OUTPUT:
    RETVAL

int
len(self)
  SV *self
  INIT:
    TickitRenderContextCell *cell;
  CODE:
    cell = (void *)SvIV(SvRV(self));
    if(cell->state == CONT)
      croak("Cannot call ->len on a CONT cell");
    RETVAL = cell->len;
  OUTPUT:
    RETVAL

SV *
pen(self)
  SV *self
  INIT:
    TickitRenderContextCell *cell;
  CODE:
    cell = (void *)SvIV(SvRV(self));
    // TODO: check state
    RETVAL = SvREFCNT_inc(cell->pen);
  OUTPUT:
    RETVAL

int
textidx(self)
  SV *self
  INIT:
    TickitRenderContextCell *cell;
  CODE:
    cell = (void *)SvIV(SvRV(self));
    if(cell->state != TEXT)
      croak("Cannot call ->textidx on a non-TEXT cell");
    RETVAL = cell->text.idx;
  OUTPUT:
    RETVAL

int
textoffs(self)
  SV *self
  INIT:
    TickitRenderContextCell *cell;
  CODE:
    cell = (void *)SvIV(SvRV(self));
    if(cell->state != TEXT)
      croak("Cannot call ->textoffs on a non-TEXT cell");
    RETVAL = cell->text.offs;
  OUTPUT:
    RETVAL

int
linemask(self)
  SV *self
  INIT:
    TickitRenderContextCell *cell;
  CODE:
    cell = (void *)SvIV(SvRV(self));
    if(cell->state != LINE)
      croak("Cannot call ->linemask on a non-LINE cell");
    RETVAL = cell->line.mask;
  OUTPUT:
    RETVAL

int
codepoint(self)
  SV *self
  INIT:
    TickitRenderContextCell *cell;
  CODE:
    cell = (void *)SvIV(SvRV(self));
    if(cell->state != CHAR)
      croak("Cannot call ->codepoint on a non-CHAR cell");
    RETVAL = cell->chr.codepoint;
  OUTPUT:
    RETVAL

void
TEXT(self,pen,textidx,textoffs)
  SV *self
  SV *pen
  int textidx
  int textoffs
  INIT:
    TickitRenderContextCell *cell;
  CODE:
    cell = (void *)SvIV(SvRV(self));
    cell->state     = TEXT;
    cell->pen       = newSVsv(pen);
    cell->text.idx  = textidx;
    cell->text.offs = textoffs;

void
ERASE(self,pen)
  SV *self
  SV *pen
  INIT:
    TickitRenderContextCell *cell;
  CODE:
    cell = (void *)SvIV(SvRV(self));
    cell->state     = ERASE;
    cell->pen       = newSVsv(pen);

void
LINE(self,pen)
  SV *self
  SV *pen
  INIT:
    TickitRenderContextCell *cell;
  CODE:
    cell = (void *)SvIV(SvRV(self));
    cell->state     = LINE;
    cell->pen       = newSVsv(pen);
    cell->line.mask = 0;

void
LINE_more(self,mask)
  SV *self
  int mask
  INIT:
    TickitRenderContextCell *cell;
  CODE:
    cell = (void *)SvIV(SvRV(self));
    cell->line.mask |= mask;

void
SKIP(self)
  SV *self
  INIT:
    TickitRenderContextCell *cell;
  CODE:
    cell = (void *)SvIV(SvRV(self));
    cell->state = SKIP;

void
CHAR(self,codepoint,pen)
  SV *self
  int codepoint
  SV *pen
  INIT:
    TickitRenderContextCell *cell;
  CODE:
    cell = (void *)SvIV(SvRV(self));
    cell->state     = CHAR;
    cell->pen       = newSVsv(pen);
    cell->chr.codepoint = codepoint;
