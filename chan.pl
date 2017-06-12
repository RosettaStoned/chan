#!/usr/bin/perl -w

use strict;
use warnings;
use forks;
use forks::shared;
use Data::Dumper;

use Chan qw( select );

sub ping($) {
    my ( $chan, $msg ) = @_;

    sleep(1);

    $chan->send({ msg => $msg });
}

my $buf_chan = Chan->new(2);

$buf_chan->send({ msg => "1" });
$buf_chan->send({ msg => "2" });

for (0 .. 1) {
    print "buff_chan: ", Dumper $buf_chan->recv();
}

my $unbuf_chan = Chan->new();

my $th = threads->new(\&ping, $unbuf_chan, "ping");
print "mitko\n";

my $data = $unbuf_chan->recv();

print "unbuf_chan data ", Dumper $data;

$th->join();

