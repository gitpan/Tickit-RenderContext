package t::TestWindow;

use Exporter 'import';
our @EXPORT_OK = qw(
   @methods
   $win
);

use Tickit::Utils qw( string_count );
use Tickit::StringPos;

our @methods;

sub goto
{
   shift;
   push @methods, [ goto => @_ ];
}

sub print
{
   shift;
   push @methods, [ print => $_[0], { $_[1]->getattrs } ];
   string_count( $_[0], my $pos = Tickit::StringPos->zero );
   return $pos;
}

sub erasech
{
   shift;
   push @methods, [ erasech => $_[0], $_[1], { $_[2]->getattrs } ];
   return Tickit::StringPos->limit_columns( $_[0] );
}

our $win = bless [], __PACKAGE__;

0x55AA;
