package Market::ML::TSNE::Optimizer;

use strict;
use warnings;
use Carp qw(croak);

sub optimize {
    my ($class, %args) = @_;

    my $p                  = $args{probabilities};
    my $n_components       = $args{n_components}       // 2;
    my $max_iter           = $args{max_iter}           // 750;
    my $learning_rate      = $args{learning_rate}      // 200.0;
    my $random_state       = $args{random_state}       // 42;
    my $verbose            = $args{verbose}            // 0;
    my $check_every        = $args{check_every}        // 25;
    my $early_exaggeration = $args{early_exaggeration} // 12.0;
    my $early_iter         = $args{early_iter}         // 250;

    my $min_gain = 0.01;

    croak "probabilities debe ser una matriz cuadrada no vacía\n"
        if ref($p) ne 'ARRAY' || !@$p;

    my $n = scalar @$p;

    for my $row (@$p) {
        croak "probabilities debe ser una matriz cuadrada\n"
            if ref($row) ne 'ARRAY' || @$row != $n;
    }

    croak "n_components debe ser mayor que cero\n"
        if $n_components <= 0;

    croak "max_iter debe ser mayor que cero\n"
        if $max_iter <= 0;

    croak "learning_rate debe ser mayor que cero\n"
        if $learning_rate <= 0;

    croak "early_iter no puede ser negativo\n"
        if $early_iter < 0;

    my $rng = _make_rng($random_state);

    # Inicialización pequeña y reproducible del embedding.
    my @y = map {
        [
            map {
                _gaussian($rng) * 1e-4
            } 1 .. $n_components
        ]
    } 1 .. $n;

    # Incremento o velocidad aplicada en la iteración anterior.
    my @velocity = map {
        [(0.0) x $n_components]
    } 1 .. $n;

    # Ganancias adaptativas por punto y dimensión.
    my @gains = map {
        [(1.0) x $n_components]
    } 1 .. $n;

    my $kl;

    for my $iter (0 .. $max_iter - 1) {

        my $factor = $iter < $early_iter
            ? $early_exaggeration
            : 1.0;

        my @num = map {
            [(0.0) x $n]
        } 1 .. $n;

        my $sum_num = 0.0;

        # -------------------------------------------------------------
        # Distribución Q en el espacio de baja dimensión.
        # Se utiliza la distribución t de Student con un grado de libertad.
        # -------------------------------------------------------------
        for my $i (0 .. $n - 2) {
            for my $j ($i + 1 .. $n - 1) {

                my $dist = 0.0;

                for my $c (0 .. $n_components - 1) {
                    my $delta = $y[$i][$c] - $y[$j][$c];
                    $dist += $delta * $delta;
                }

                my $value = 1.0 / (1.0 + $dist);

                $num[$i][$j] = $value;
                $num[$j][$i] = $value;

                $sum_num += 2.0 * $value;
            }
        }

        $sum_num = 1e-12 if $sum_num < 1e-12;

        # -------------------------------------------------------------
        # Gradiente de la divergencia KL.
        # -------------------------------------------------------------
        my @gradient = map {
            [(0.0) x $n_components]
        } 1 .. $n;

        for my $i (0 .. $n - 2) {
            for my $j ($i + 1 .. $n - 1) {

                my $q = $num[$i][$j] / $sum_num;
                $q = 1e-12 if $q < 1e-12;

                my $multiplier =
                    4.0
                    * (($factor * $p->[$i][$j]) - $q)
                    * $num[$i][$j];

                for my $c (0 .. $n_components - 1) {

                    my $delta = $y[$i][$c] - $y[$j][$c];
                    my $g = $multiplier * $delta;

                    $gradient[$i][$c] += $g;
                    $gradient[$j][$c] -= $g;
                }
            }
        }

        # -------------------------------------------------------------
        # Al terminar early exaggeration se amortigua la velocidad.
        #
        # Durante la exageración temprana pueden acumularse incrementos
        # grandes. Conservarlos completamente al retirar la exageración
        # puede producir una transición brusca.
        # -------------------------------------------------------------
        if ($iter == $early_iter) {
            for my $i (0 .. $n - 1) {
                for my $c (0 .. $n_components - 1) {
                    $velocity[$i][$c] *= 0.25;
                }
            }
        }

        # -------------------------------------------------------------
        # Momentum.
        #
        # No se aumenta el momentum exactamente en la misma iteración
        # en la que termina early exaggeration. Se mantienen 50
        # iteraciones de transición con momentum 0.5.
        # -------------------------------------------------------------
        my $momentum;

        if ($iter < ($early_iter + 50)) {
            $momentum = 0.5;
        }
        else {
            $momentum = 0.8;
        }

        # -------------------------------------------------------------
        # Ganancias adaptativas y actualización del embedding.
        #
        # La dirección del gradiente actual se compara con la velocidad
        # anterior, no con el gradiente anterior.
        #
        # Si ambas direcciones coinciden, la ganancia disminuye.
        # Si son opuestas o la velocidad anterior es cero, aumenta.
        # -------------------------------------------------------------
        for my $i (0 .. $n - 1) {
            for my $c (0 .. $n_components - 1) {

                my $gradient_value = $gradient[$i][$c];
                my $previous_velocity = $velocity[$i][$c];

                my $same_sign =
                       ($gradient_value > 0.0 && $previous_velocity > 0.0)
                    || ($gradient_value < 0.0 && $previous_velocity < 0.0);

                if ($same_sign) {
                    $gains[$i][$c] *= 0.8;
                }
                else {
                    $gains[$i][$c] += 0.2;
                }

                $gains[$i][$c] = $min_gain
                    if $gains[$i][$c] < $min_gain;

                $velocity[$i][$c] =
                      $momentum * $previous_velocity
                    - $learning_rate
                    * $gains[$i][$c]
                    * $gradient_value;

                $y[$i][$c] += $velocity[$i][$c];
            }
        }

        # Evita que todo el embedding se desplace respecto al origen.
        _center(\@y, $n_components);

        if (
            $iter == $max_iter - 1
            || ($verbose && (($iter + 1) % $check_every == 0))
        ) {
            $kl = _kl_divergence($p, \@num, $sum_num);

            if ($verbose) {
                printf(
                    "[t-SNE] Iteración %d/%d - KL=%.8f%s\n",
                    $iter + 1,
                    $max_iter,
                    $kl,
                    $iter < $early_iter
                        ? ' (early exaggeration)'
                        : ''
                );
            }
        }
    }

    return {
        embedding     => \@y,
        kl_divergence => $kl,
        iterations    => $max_iter,
    };
}

sub _center {
    my ($y, $components) = @_;

    my $n = scalar @$y;

    return if $n == 0;

    for my $c (0 .. $components - 1) {

        my $mean = 0.0;

        $mean += $_->[$c] for @$y;
        $mean /= $n;

        $_->[$c] -= $mean for @$y;
    }
}

sub _kl_divergence {
    my ($p, $num, $sum_num) = @_;

    my $n = scalar @$p;
    my $kl = 0.0;

    for my $i (0 .. $n - 2) {
        for my $j ($i + 1 .. $n - 1) {

            my $pv = $p->[$i][$j];

            next if $pv <= 0.0;

            my $qv = $num->[$i][$j] / $sum_num;
            $qv = 1e-12 if $qv < 1e-12;

            $kl += 2.0 * $pv * log($pv / $qv);
        }
    }

    return $kl;
}

sub _make_rng {
    my ($seed) = @_;

    $seed = 42 if !defined $seed;
    $seed = int($seed) & 0x7fffffff;
    $seed = 1 if $seed == 0;

    return sub {

        # Generador congruencial lineal determinista de 31 bits.
        # Es local al optimizador y no modifica rand()/srand() globales.
        $seed = (1103515245 * $seed + 12345) % 2147483648;

        return $seed / 2147483648.0;
    };
}

sub _gaussian {
    my ($rng) = @_;

    my $u1 = $rng->();
    my $u2 = $rng->();

    $u1 = 1e-12 if $u1 < 1e-12;

    return sqrt(-2.0 * log($u1))
        * cos(2.0 * 3.141592653589793 * $u2);
}

1;