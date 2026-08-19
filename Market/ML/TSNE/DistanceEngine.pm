package Market::ML::TSNE::DistanceEngine;

use strict;
use warnings;
use Carp qw(croak);

sub pairwise_squared {
    my ($class, $vectors) = @_;
    croak "vectors debe ser ARRAY y no puede estar vacío\n"
        if ref($vectors) ne 'ARRAY' || !@$vectors;

    my $n = scalar @$vectors;
    my $d = scalar @{$vectors->[0] // []};
    croak "Cada vector debe contener al menos una dimensión\n" if !$d;

    for my $row (@$vectors) {
        croak "Todos los vectores deben tener $d dimensiones\n"
            if ref($row) ne 'ARRAY' || @$row != $d;
    }

    my @dist = map { [(0) x $n] } 1 .. $n;
    for my $i (0 .. $n - 2) {
        my $xi = $vectors->[$i];
        for my $j ($i + 1 .. $n - 1) {
            my $xj = $vectors->[$j];
            my $sum = 0.0;
            for my $k (0 .. $d - 1) {
                my $delta = $xi->[$k] - $xj->[$k];
                $sum += $delta * $delta;
            }
            $dist[$i][$j] = $sum;
            $dist[$j][$i] = $sum;
        }
    }
    return \@dist;
}

sub cross_squared {
    my ($class, $left, $right) = @_;
    croak "left y right deben ser ARRAY no vacíos\n"
        if ref($left) ne 'ARRAY' || !@$left || ref($right) ne 'ARRAY' || !@$right;
    my $d = scalar @{$left->[0] // []};
    croak "Los vectores deben tener dimensiones válidas\n" if !$d;

    my @dist;
    for my $a (@$left) {
        croak "Dimensión inconsistente en left\n" if ref($a) ne 'ARRAY' || @$a != $d;
        my @row;
        for my $b (@$right) {
            croak "Dimensión inconsistente en right\n" if ref($b) ne 'ARRAY' || @$b != $d;
            my $sum = 0.0;
            for my $k (0 .. $d - 1) {
                my $delta = $a->[$k] - $b->[$k];
                $sum += $delta * $delta;
            }
            push @row, $sum;
        }
        push @dist, \@row;
    }
    return \@dist;
}

1;
