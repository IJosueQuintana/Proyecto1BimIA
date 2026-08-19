package Market::ML::GaussianMixtureModel;

use strict;
use warnings;
use List::Util qw(sum max);
use POSIX qw(log exp);

sub new {
    my ($class, %args) = @_;
    my $components = $args{components} // 3;
    die "components debe ser mayor que cero\n" if $components < 1;

    return bless {
        components      => $components,
        max_iterations  => $args{max_iterations} // 150,
        tolerance       => $args{tolerance} // 1e-5,
        regularization  => $args{regularization} // 1e-4,
        seed            => $args{seed} // 42,
        weights         => undef,
        means           => undef,
        variances       => undef,
        converged       => 0,
        iterations      => 0,
        log_likelihood  => undef,
        dimension       => undef,
    }, $class;
}

sub fit {
    my ($self, %args) = @_;
    my $vectors = $args{vectors} // [];
    _validate_vectors($vectors);

    my $n = scalar(@$vectors);
    my $d = scalar(@{$vectors->[0]});
    my $k = $self->{components};
    die "GMM requiere al menos tantos ejemplos como componentes\n" if $n < $k;

    $self->{dimension} = $d;
    my $means = _initialize_means($vectors, $k, $self->{seed});
    my $global_variance = _global_variance($vectors, $self->{regularization});
    my @variances = map { [@$global_variance] } 1 .. $k;
    my @weights = map { 1 / $k } 1 .. $k;

    my $previous_ll;
    my $responsibilities;
    my $current_ll;

    for my $iteration (1 .. $self->{max_iterations}) {
        ($responsibilities, $current_ll) = _expectation(
            $vectors, \@weights, $means, \@variances
        );

        my (@new_weights, @new_means, @new_variances);
        for my $component (0 .. $k - 1) {
            my $nk = sum(map { $responsibilities->[$_][$component] } 0 .. $n - 1);

            # Evita componentes vacíos reinicializándolos con un punto alejado.
            if ($nk < 1e-8) {
                my $index = ($component * 997 + $self->{seed}) % $n;
                push @new_weights, 1 / $n;
                push @new_means, [@{$vectors->[$index]}];
                push @new_variances, [@$global_variance];
                next;
            }

            push @new_weights, $nk / $n;
            my @mean = (0) x $d;
            for my $i (0 .. $n - 1) {
                my $r = $responsibilities->[$i][$component];
                for my $j (0 .. $d - 1) {
                    $mean[$j] += $r * $vectors->[$i][$j];
                }
            }
            $_ /= $nk for @mean;
            push @new_means, \@mean;

            my @variance = (0) x $d;
            for my $i (0 .. $n - 1) {
                my $r = $responsibilities->[$i][$component];
                for my $j (0 .. $d - 1) {
                    my $delta = $vectors->[$i][$j] - $mean[$j];
                    $variance[$j] += $r * $delta * $delta;
                }
            }
            for my $j (0 .. $d - 1) {
                $variance[$j] = $variance[$j] / $nk + $self->{regularization};
            }
            push @new_variances, \@variance;
        }

        my $weight_sum = sum(@new_weights) || 1;
        $_ /= $weight_sum for @new_weights;
        @weights = @new_weights;
        $means = \@new_means;
        @variances = @new_variances;

        $self->{iterations} = $iteration;
        if (defined $previous_ll && abs($current_ll - $previous_ll) <=
            $self->{tolerance} * (1 + abs($previous_ll))) {
            $self->{converged} = 1;
            last;
        }
        $previous_ll = $current_ll;
    }

    # Verosimilitud final correspondiente a los parámetros finales.
    (undef, $current_ll) = _expectation($vectors, \@weights, $means, \@variances);
    $self->{weights} = \@weights;
    $self->{means} = $means;
    $self->{variances} = \@variances;
    $self->{log_likelihood} = $current_ll;
    return $self;
}

sub predict_components {
    my ($self, %args) = @_;
    my $vectors = $args{vectors} // [];
    $self->_require_fitted;
    _validate_vectors($vectors, $self->{dimension});

    my @predictions;
    for my $vector (@$vectors) {
        my @scores = map {
            log($self->{weights}[$_] + 1e-300)
                + _log_gaussian_diag($vector, $self->{means}[$_], $self->{variances}[$_])
        } 0 .. $self->{components} - 1;
        my $best = 0;
        for my $component (1 .. $#scores) {
            $best = $component if $scores[$component] > $scores[$best];
        }
        push @predictions, $best;
    }
    return \@predictions;
}

sub predict_proba {
    my ($self, %args) = @_;
    my $vectors = $args{vectors} // [];
    $self->_require_fitted;
    _validate_vectors($vectors, $self->{dimension});
    my ($responsibilities) = _expectation(
        $vectors, $self->{weights}, $self->{means}, $self->{variances}
    );
    return $responsibilities;
}

sub score {
    my ($self, %args) = @_;
    my $vectors = $args{vectors} // [];
    $self->_require_fitted;
    _validate_vectors($vectors, $self->{dimension});
    my (undef, $ll) = _expectation(
        $vectors, $self->{weights}, $self->{means}, $self->{variances}
    );
    return $ll;
}

sub bic {
    my ($self, %args) = @_;
    my $vectors = $args{vectors} // [];
    my $n = scalar(@$vectors);
    die "No se puede calcular BIC con cero filas\n" if !$n;
    my $ll = $self->score(vectors => $vectors);
    my $k = $self->{components};
    my $d = $self->{dimension};
    my $parameter_count = ($k - 1) + $k * $d + $k * $d; # pesos + medias + varianzas diagonales
    return -2 * $ll + $parameter_count * log($n);
}

sub components     { return $_[0]{components}; }
sub converged      { return $_[0]{converged}; }
sub iterations     { return $_[0]{iterations}; }
sub log_likelihood { return $_[0]{log_likelihood}; }
sub weights        { return [@{$_[0]{weights} // []}]; }
sub means          { return [map { [@$_] } @{$_[0]{means} // []}]; }
sub variances      { return [map { [@$_] } @{$_[0]{variances} // []}]; }

sub _require_fitted {
    my ($self) = @_;
    die "GMM todavía no fue entrenado\n" if ref($self->{means}) ne 'ARRAY';
}

sub _expectation {
    my ($vectors, $weights, $means, $variances) = @_;
    my $k = scalar(@$weights);
    my @responsibilities;
    my $log_likelihood = 0;

    for my $vector (@$vectors) {
        my @log_scores = map {
            log($weights->[$_] + 1e-300)
                + _log_gaussian_diag($vector, $means->[$_], $variances->[$_])
        } 0 .. $k - 1;
        my $log_total = _log_sum_exp(\@log_scores);
        $log_likelihood += $log_total;
        push @responsibilities, [map { exp($_ - $log_total) } @log_scores];
    }
    return (\@responsibilities, $log_likelihood);
}

sub _log_gaussian_diag {
    my ($vector, $mean, $variance) = @_;
    my $log_two_pi = log(2 * 3.14159265358979323846);
    my $result = 0;
    for my $j (0 .. $#$vector) {
        my $var = $variance->[$j] > 1e-15 ? $variance->[$j] : 1e-15;
        my $delta = $vector->[$j] - $mean->[$j];
        $result += -0.5 * ($log_two_pi + log($var) + ($delta * $delta) / $var);
    }
    return $result;
}

sub _log_sum_exp {
    my ($values) = @_;
    my $maximum = max(@$values);
    return $maximum + log(sum(map { exp($_ - $maximum) } @$values));
}

sub _initialize_means {
    my ($vectors, $k, $seed) = @_;
    my $n = scalar(@$vectors);
    my @selected = ($seed % $n);
    my %used = ($selected[0] => 1);

    while (@selected < $k) {
        my ($best_index, $best_distance) = (undef, -1);
        for my $i (0 .. $n - 1) {
            next if $used{$i};
            my $nearest;
            for my $selected_index (@selected) {
                my $distance = _squared_distance($vectors->[$i], $vectors->[$selected_index]);
                $nearest = $distance if !defined($nearest) || $distance < $nearest;
            }
            if (!defined($best_index) || $nearest > $best_distance) {
                ($best_index, $best_distance) = ($i, $nearest);
            }
        }
        $best_index = scalar(@selected) % $n if !defined $best_index;
        push @selected, $best_index;
        $used{$best_index} = 1;
    }
    return [map { [@{$vectors->[$_]}] } @selected];
}

sub _global_variance {
    my ($vectors, $regularization) = @_;
    my $n = scalar(@$vectors);
    my $d = scalar(@{$vectors->[0]});
    my @means = (0) x $d;
    for my $vector (@$vectors) {
        $means[$_] += $vector->[$_] for 0 .. $d - 1;
    }
    $_ /= $n for @means;

    my @variance = (0) x $d;
    for my $vector (@$vectors) {
        for my $j (0 .. $d - 1) {
            my $delta = $vector->[$j] - $means[$j];
            $variance[$j] += $delta * $delta;
        }
    }
    for my $j (0 .. $d - 1) {
        $variance[$j] = $variance[$j] / $n + $regularization;
    }
    return \@variance;
}

sub _squared_distance {
    my ($a, $b) = @_;
    my $sum = 0;
    for my $j (0 .. $#$a) {
        my $delta = $a->[$j] - $b->[$j];
        $sum += $delta * $delta;
    }
    return $sum;
}

sub _validate_vectors {
    my ($vectors, $expected_dimension) = @_;
    die "vectors debe ser ARRAY\n" if ref($vectors) ne 'ARRAY';
    die "No se puede trabajar con cero vectores\n" if !@$vectors;
    my $dimension = scalar(@{$vectors->[0] // []});
    die "Los vectores no pueden tener dimensión cero\n" if !$dimension;
    die "Dimensión incompatible con el GMM entrenado\n"
        if defined($expected_dimension) && $dimension != $expected_dimension;
    for my $vector (@$vectors) {
        die "Todos los vectores deben tener la misma dimensión\n"
            if ref($vector) ne 'ARRAY' || @$vector != $dimension;
        for my $value (@$vector) {
            die "GMM recibió un valor no numérico\n"
                if !defined($value) || $value !~ /^[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?$/;
        }
    }
}

1;
