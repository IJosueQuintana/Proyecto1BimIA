package Market::ML::TSNE::ProbabilityMatrix;

use strict;
use warnings;
use Carp qw(croak);

sub symmetric_joint {
    my ($class, %args) = @_;
    my $conditional = $args{conditional};
    my $minimum = $args{minimum} // 1e-12;
    croak "conditional debe ser una matriz cuadrada no vacía\n"
        if ref($conditional) ne 'ARRAY' || !@$conditional;

    my $n = scalar @$conditional;
    my @joint = map { [(0.0) x $n] } 1 .. $n;
    my $sum = 0.0;

    for my $i (0 .. $n - 2) {
        for my $j ($i + 1 .. $n - 1) {
            my $value = ($conditional->[$i][$j] + $conditional->[$j][$i]) / (2.0 * $n);
            $value = $minimum if $value < $minimum;
            $joint[$i][$j] = $value;
            $joint[$j][$i] = $value;
            $sum += 2.0 * $value;
        }
    }

    croak "No fue posible construir una matriz de probabilidades válida\n" if $sum <= 0;
    for my $i (0 .. $n - 1) {
        for my $j (0 .. $n - 1) {
            next if $i == $j;
            $joint[$i][$j] /= $sum;
        }
    }
    return \@joint;
}

sub exaggerate {
    my ($class, $matrix, $factor) = @_;
    my @copy = map { [map { $_ * $factor } @$_] } @$matrix;
    return \@copy;
}

1;
