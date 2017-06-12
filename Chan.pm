package Chan;

require Exporter;
@ISA = qw( Exporter );
@EXPORT_OK = qw( select ); 

use strict;
use forks;
use forks::shared;
use warnings;

use Time::HiRes qw( time );

use Carp;
use Queue;

use Data::Dumper;

sub new($;$)
{
    my ( $class, $capacity ) = @_;

    my %self :shared;
    my %data :shared;

    my ($r_mu,
        $w_mu,
        $m_mu,
        $r_cond,
        $w_cond,
        $closed,
        $r_waiting,
        $w_waiting) :shared = (0) x 8;

    $self{queue} =  defined $capacity &&
        $capacity > 0
        ? Queue->new( $capacity )
        : undef;
    $self{data} = \%data;

    $self{r_mu} = \$r_mu;
    $self{w_mu} = \$w_mu;
    $self{m_mu} = \$m_mu;
    $self{r_cond} = \$r_cond;
    $self{w_cond} = \$w_cond;
    $self{closed} = \$closed;
    $self{r_waiting} = \$r_waiting;
    $self{w_waiting} = \$w_waiting;

    bless \%self, $class;

    return \%self;
}


sub close($)
{
    my ( $self ) = @_;

    lock( ${ $$self{ m_mu } } );

    if( !${ $$self{ closed } } ) {

        ${ $$self{ closed } } = 1;

        cond_broadcast( ${ $$self{ r_cond } } );
        cond_broadcast( ${ $$self{ w_cond } } );
    }
}

sub is_closed($)
{
    my ( $self ) = @_;

    lock ( ${ $$self{ m_mu } } );
    return ${ $$self{ closed } };
}

sub is_buffered($)
{
    my ( $self ) = @_;

    return defined $$self{queue};
}

sub send($$)
{
    my ( $self, $data ) = @_;

    if( $self->is_closed() ) {
        croak 'error: chan is closed\n';
    }

    if( $self->is_buffered() ) {
        $self->buffered_send($data);
    } else {
        $self->unbuffered_send($data);
    }

}

sub recv($)
{
    my ( $self ) = @_;

    return $self->is_buffered()
        ? $self->buffered_recv()
        : $self->unbuffered_recv();
}

sub buffered_send($$)
{
    my ( $self, $data ) = @_;

    lock( ${ $$self{ m_mu } } );

    while( $$self{queue}{size} == $$self{queue}{capacity} ) {
        ${ $$self{ w_waiting } }++;
        cond_wait( ${ $$self{ w_cond } }, ${ $$self{ m_mu } } );
        ${ $$self{ w_waiting } }--;
    }

    $$self{queue}->add( $data );

    if( ${ $$self{ r_waiting } } > 0 ) {
        cond_signal( ${ $$self{ r_cond } } );
    }
}

sub buffered_recv($)
{
    my ( $self ) = @_;

    lock( ${ $$self{ m_mu } } );

    while( $$self{queue}{size} == 0 ) {

        if( ${ $$self{ closed } } ) {
            croak 'error: chan is closed\n';
        }

        ${ $$self{ r_waiting } }++;
        cond_wait( ${ $$self{ r_cond } }, ${ $$self{ m_mu } } );
        ${ $$self{ r_waiting } }--;
    }

    my $data = $$self{queue}->remove();

    if( ${ $$self{ w_waiting } } > 0 ) {
        cond_signal( ${ $$self{ w_cond } } );
    }

    return ${ $data };
}

sub unbuffered_send($$)
{
    my ( $self, $data ) = @_;


    lock( ${ $$self{ w_mu } } );
    lock( ${ $$self{ m_mu } } );


    if( ${ $$self{ closed } } ) {
        croak 'error: chan is closed\n';
    }

    $$self{data} = &share(\$data);
    $$self{data} = \$data;

    ${ $$self{ w_waiting } }++;


    if( ${ $$self{ r_waiting } } > 0 ) {
        no warnings 'threads';
        cond_signal( ${ $$self{ r_cond } } );
    }

    cond_wait( ${ $$self{ w_cond } }, ${ $$self{ m_mu } } );

}

sub unbuffered_recv($)
{
    my ( $self ) = @_;

    lock ( ${ $$self{ r_mu } } );
    lock ( ${ $$self{ m_mu } } );

    while( !${ $$self{ closed } } && !${ $$self{ w_waiting } } ) {
        ${ $$self{ r_waiting } }++;
        cond_wait( ${ $$self{ r_cond } }, ${ $$self{ m_mu } } );
        ${ $$self{ r_waiting } }--;
    }

    if( ${ $$self{ closed } } ) {
        croak 'error: chan is closed\n';
    }

    my $data = $$self{data};
    ${ $$self{ w_waiting } }--;

    {
        no warnings 'threads';
        cond_signal( ${ $$self{ w_cond } } );
    }

    return ${ $data };
}


sub size($)
{
    my ( $self ) = @_;

    my $size = 0;

    if( $self->is_buffered() ) {
        lock( ${ $$self{ m_mu } } );
        $size = $$self{queue}{size};
    }

    return $size;
}

sub can_send($)
{
    my ( $self ) = @_;

    lock( ${ $$self{ m_mu } } );

    return $self->is_buffered()
        ? $$self{queue}{size} < $$self{queue}{capacity}
        : ${ $$self{ r_waiting } } > 0;
}


sub can_recv($)
{
    my ( $self ) = @_;

    if( $self->is_buffered() ) {
        return $self->size() > 0;
    }

    lock( ${ $$self{ m_mu } } );
    return ${ $$self{ w_waiting } } > 1;
}

sub select
{
    my ( $recv_chans, $send_chans ) = @_;

    my $count = 0;
    my $candidates = [];

    for my $chan ( @{ $recv_chans } ) {

        if( $chan->can_recv() ) {

            my $op = {
                recv => 1,
                chan => $chan,
                index => $count++
            };

            push( @{ $candidates }, $op );
        }

    }

    for my $chan ( @{ $send_chans } ) {

        if( $chan->can_send() ) {

            my $op = {
                recv => 0,
                chan => $chan,
                index => $count++,
            };

            push ( @{ $candidates }, $op );
        }
    }

    srand( time() );
    
    my $select = $$candidates[rand % $count];
    my $chan = $$select{chan};

    if( $$select{recv} ) {
        $chan->recv();
    } else {
        $chan->send( $$chan{data} );
    }

    return $$select{index};
}



1;
