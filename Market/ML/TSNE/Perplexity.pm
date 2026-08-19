package Market::ML::TSNE::Perplexity;

use strict;
use warnings;
use Carp qw(croak);
use POSIX qw(log);

sub conditional_probabilities {
    my ($class, %args) = @_;
    my $distances = $args{distances};
    my $perplexity = $args{perplexity} // 30;
    my $tolerance = $args{tolerance} // 1e-5;
    my $max_iter = $args{max_iter} // 60;

    croak "distances debe ser una matriz cuadrada no vacía\n"
        if ref($distances) ne 'ARRAY' || !@$distances;
    my $n = scalar @$distances;
    croak "perplexity debe ser mayor que cero y menor que el número de muestras\n"
        if $perplexity <= 0 || $perplexity >= $n;

    my $target_entropy = log($perplexity);
    my @conditional;
    my @betas;

    for my $i (0 .. $n - 1) {
        my ($beta, $beta_min, $beta_max) = (1.0, undef, undef);
        my ($prob, $entropy);

        for my $iter (1 .. $max_iter) {
            ($prob, $entropy) = _row_probabilities($distances->[$i], $i, $beta);
            my $diff = $entropy - $target_entropy;
            last if abs($diff) <= $tolerance;

            if ($diff > 0) {
                $beta_min = $beta;
                $beta = defined($beta_max) ? ($beta + $beta_max) / 2.0 : $beta * 2.0;
            }
            else {
                $beta_max = $beta;
                $beta = defined($beta_min) ? ($beta + $beta_min) / 2.0 : $beta / 2.0;
            }
        }

        push @conditional, $prob;
        push @betas, $beta;
    }

    return {
        probabilities => \@conditional,
        betas          => \@betas,
    };
}

sub _row_probabilities {
    my ($row, $self_index, $beta) = @_;
    my $n = scalar @$row;
    my @weights = (0.0) x $n;
    my $sum = 0.0;

    for my $j (0 .. $n - 1) {
        next if $j == $self_index;
        my $exponent = -$row->[$j] * $beta;
        $exponent = -700 if $exponent < -700;
        my $weight = exp($exponent);
        $weights[$j] = $weight;
        $sum += $weight;
    }

    if ($sum <= 1e-300) {
        my $uniform = 1.0 / ($n - 1);
        for my $j (0 .. $n - 1) {
            $weights[$j] = $j == $self_index ? 0.0 : $uniform;
        }
        return (\@weights, log($n - 1));
    }

    my $weighted_distance = 0.0;
    for my $j (0 .. $n - 1) {
        next if $j == $self_index;
        $weights[$j] /= $sum;
        $weighted_distance += $weights[$j] * $row->[$j];
    }

    my $entropy = log($sum) + $beta * $weighted_distance;
    return (\@weights, $entropy);
}

1;
