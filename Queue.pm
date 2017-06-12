package Queue;

use strict;
use warnings;
use forks;
use forks::shared;

use Carp;

sub new($$) 
{
    my ( $class, $capacity ) = @_;

    if( ref $capacity ) {
        croak "error: capacity cannot be ref\n";
    }

    if( $capacity <= 0 && 
        $capacity !~ /^\d+$/) {
        croak "error: capacity must be positive integer number\n";
    }

    my %self :shared;
    my @data :shared;

    my $capa :shared = $capacity;
    my ($size,
        $next) :shared = (0) x 2;

    $self{data} = \@data;
    $self{capacity} = \$capa;
    $self{size} = \$size;
    $self{next} = \$next;

    bless \%self, $class;

    return \%self;
}

sub at_capacity($) 
{
    my ( $self ) = @_;

    return ${ $$self{ size } } >= ${ $$self{ capacity } };
}

sub add($$)
{
    my ( $self, $value ) = @_; 

    if( $self->at_capacity ) {
        die "error: exceed queue capacity\n";
    }

    my $pos = ${ $$self{ next } } + ${ $$self{ size } };
    if( $pos >= ${ $$self{ capacity } } ) {
        $pos -= ${ $$self{ capacity } };
    }

    $$self{data}[$pos] = &share($value);
    $$self{data}[$pos] = \$value;

    ${ $$self{ size } }++;
}

sub remove($)
{
    my ( $self ) = @_;

    my $value = undef;

    if( ${ $$self{ size } } > 0 ) {

        $value = $$self{data}[${ $$self{ next } }];
        ${ $$self{ next } }++;
        ${ $$self{ size } }--;

        if( ${ $$self{ next } } >= ${ $$self{ capacity } } ) {
            ${ $$self{ next } } -= ${ $$self{ capacity } };
        }
    }

    return $value;
}

sub peak($)
{
    my ( $self ) = @_;

    return ${ $$self{ size } }
        ? $$self{data}[${ $$self{ next } }]
        : undef;
}

1;
