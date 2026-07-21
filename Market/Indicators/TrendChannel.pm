package Market::Indicators::TrendChannel;

use strict;
use warnings;

sub new {
    my ($class, %args) = @_;

    my $self = {
        # Cantidad máxima de pivotes recientes que se evaluarán.
        pivot_lookback =>
            $args{pivot_lookback} // 16,

        # Separación mínima entre los dos pivotes que forman una línea.
        min_pivot_distance =>
            $args{min_pivot_distance} // 5,
        
        min_touch_distance =>
            $args{min_touch_distance} // 5,

        # Distancia máxima entre un pivote y la línea para considerarlo toque.
        tolerance_atr_mult =>
            $args{tolerance_atr_mult} // 0.25,

        # Tolerancia para evitar considerar una pequeña mecha como ruptura.
        break_atr_mult =>
            $args{break_atr_mult} // 0.20,

        # Número mínimo de cierres consecutivos fuera de la línea.
        break_confirm_bars =>
            $args{break_confirm_bars} // 1,

        # Una línea queda confirmada desde este número de contactos.
        confirmed_touches =>
            $args{confirmed_touches} // 3,

        # Cantidad máxima de líneas por dirección.
        max_lines_per_side =>
            $args{max_lines_per_side} // 2,
    };

    return bless $self, $class;
}

sub calculate {
    my ($self, %args) = @_;

    my $pivots =
        ref($args{pivots}) eq 'ARRAY'
        ? $args{pivots}
        : [];

    my $candles =
        ref($args{candles}) eq 'ARRAY'
        ? $args{candles}
        : [];

    my $atr =
        ref($args{atr}) eq 'ARRAY'
        ? $args{atr}
        : [];

    my $until_index =
        defined $args{until_index}
        ? $args{until_index}
        : $#$candles;

    # Rango actualmente visible en el gráfico.
    my $visible_start =
        defined $args{visible_start}
        ? $args{visible_start}
        : 0;

    my $visible_end =
        defined $args{visible_end}
        ? $args{visible_end}
        : $until_index;

    $visible_start = 0
        if $visible_start < 0;

    $visible_end = $until_index
        if $visible_end > $until_index;

    return $self->_empty_result(
        visible_start => $visible_start,
        visible_end   => $visible_end,
    )
        if $visible_end <= $visible_start;

    # Pequeño margen izquierdo para permitir que una línea nacida
    # poco antes de la ventana continúe siendo relevante.
    my $visible_bars =
        $visible_end - $visible_start + 1;

    my $left_margin =
        int($visible_bars * 10);

    $left_margin = 2000
        if $left_margin < 2000;

    $left_margin = 6000
        if $left_margin > 6000;

    my $analysis_start =
        $visible_start - $left_margin;

    $analysis_start = 0
        if $analysis_start < 0;
# Linea de manera momentanea para saber pivotes
    print "\n";
print "=============================\n";
print "PIVOTES RECIBIDOS\n";

print "Total pivotes: "
    . scalar(@$pivots)
    . "\n";

if (@$pivots) {

    print "Primer pivote:\n";

    print "index = "
        . ($pivots->[0]{index} // 'undef')
        . "\n";

    print "price = "
        . ($pivots->[0]{price} // 'undef')
        . "\n";

    print "type = "
        . ($pivots->[0]{type} // 'undef')
        . "\n";

    print "Último pivote:\n";

    print "index = "
        . ($pivots->[-1]{index} // 'undef')
        . "\n";

    print "price = "
        . ($pivots->[-1]{price} // 'undef')
        . "\n";

    print "type = "
        . ($pivots->[-1]{type} // 'undef')
        . "\n";
}

print "=============================\n";    

    # Solo se utilizan pivotes pertenecientes al campo visible
    # más un margen pequeño hacia la izquierda.
my @usable_pivots;

my $discarded_invalid = 0;
my $discarded_before  = 0;
my $discarded_after   = 0;

for my $pivot (@$pivots) {

    if (
        !$pivot
        || ref($pivot) ne 'HASH'
        || !defined $pivot->{index}
        || !defined $pivot->{price}
        || !defined $pivot->{type}
    ) {
        $discarded_invalid++;
        next;
    }

    # Forzamos una comparación numérica.
    my $pivot_index =
        0 + $pivot->{index};

    if ($pivot_index < $analysis_start) {
        $discarded_before++;
        next;
    }

    if (
        $pivot_index > $visible_end
        || $pivot_index > $until_index
    ) {
        $discarded_after++;
        next;
    }

    # Guardamos el índice normalizado.
    $pivot->{index} =
        $pivot_index;

    push @usable_pivots,
        $pivot;
}

@usable_pivots =
    sort {
        $a->{index} <=> $b->{index}
    } @usable_pivots;

print "\n";
print "========================================\n";
print "FILTRO DE PIVOTES TRENDLINE\n";

print "analysis_start: "
    . $analysis_start
    . "\n";

print "visible_end: "
    . $visible_end
    . "\n";

print "until_index: "
    . $until_index
    . "\n";

print "Recibidos: "
    . scalar(@$pivots)
    . "\n";

print "Inválidos: "
    . $discarded_invalid
    . "\n";

print "Anteriores al rango: "
    . $discarded_before
    . "\n";

print "Posteriores al rango: "
    . $discarded_after
    . "\n";

print "Utilizables: "
    . scalar(@usable_pivots)
    . "\n";

for my $pivot (@usable_pivots) {
    print join(
        ' ',
        'index=' . $pivot->{index},
        'type='  . $pivot->{type},
        'price=' . $pivot->{price},
    ) . "\n";
}

print "========================================\n";

    # return $self->_empty_result(
    #     visible_start  => $visible_start,
    #     visible_end    => $visible_end,
    #     analysis_start => $analysis_start,
    #     pivots_used    => scalar(@usable_pivots),
    # )
    #     if @usable_pivots < 3;

    my $lookback =
        $self->{pivot_lookback};

    if (@usable_pivots > $lookback) {
        @usable_pivots =
            @usable_pivots[
                @usable_pivots - $lookback
                ..
                $#usable_pivots
            ];
    }

    my @lows =
        grep {
            uc($_->{type} // '') eq 'LOW'
        } @usable_pivots;

    my @highs =
        grep {
            uc($_->{type} // '') eq 'HIGH'
        } @usable_pivots;
    
    return $self->_empty_result(
        visible_start  => $visible_start,
        visible_end    => $visible_end,
        analysis_start => $analysis_start,
        pivots_used    => scalar(@usable_pivots),
    )
        if @lows < 3
        && @highs < 3;

    my @bullish =
        $self->_generate_candidates(
            type        => 'BULLISH',
            pivots      => \@lows,
            all_pivots  => \@usable_pivots,
            candles     => $candles,
            atr         => $atr,

            # La validación termina en el borde visible,
            # no necesariamente en la última vela total.
            until_index => $visible_end,
        );

    my @bearish =
        $self->_generate_candidates(
            type        => 'BEARISH',
            pivots      => \@highs,
            all_pivots  => \@usable_pivots,
            candles     => $candles,
            atr         => $atr,
            until_index => $visible_end,
        );

    my @all =
        sort {
               ($b->{score} // 0) <=> ($a->{score} // 0)
            || ($b->{touches} // 0) <=> ($a->{touches} // 0)
            || ($b->{second_index} // 0)
                <=> ($a->{second_index} // 0)
        } (@bullish, @bearish);

    my @candidates =
        grep {
            ($_->{status} // '') eq 'CANDIDATE'
        } @all;

    my @confirmed =
        grep {
            ($_->{status} // '') eq 'CONFIRMED'
        } @all;

    my @broken =
        grep {
            ($_->{status} // '') eq 'BROKEN'
        } @all;

    my @trendlines =
        $self->_select_visible_lines(
            lines => \@all,
        );

    return {
        trendlines => \@trendlines,
        candidates => \@candidates,
        confirmed  => \@confirmed,
        broken     => \@broken,
        channels   => [],

        visible_start => $visible_start,
        visible_end   => $visible_end,
        analysis_start => $analysis_start,

        audit => {
            pivots_used =>
                scalar(@usable_pivots),

            bullish_candidates =>
                scalar(@bullish),

            bearish_candidates =>
                scalar(@bearish),

            confirmed_lines =>
                scalar(@confirmed),

            visible_lines =>
                scalar(@trendlines),

            visible_start =>
                $visible_start,

            visible_end =>
                $visible_end,

            analysis_start =>
                $analysis_start,
        },
    };
}

sub _generate_candidates {
    my ($self, %args) = @_;

    my $type =
        $args{type};

    my $pivots =
        $args{pivots} || [];

    my $all_pivots =
        $args{all_pivots} || [];

    my $candles =
        $args{candles} || [];

    my $atr =
        $args{atr} || [];

    my $until_index =
        $args{until_index};

    # Ahora necesitamos al menos tres pivotes del mismo tipo.
    return ()
        if @$pivots < 3;

    my @lines;

    for my $i (0 .. $#$pivots - 2) {
        my $first =
            $pivots->[$i];

        next if !$first;

        for my $j ($i + 1 .. $#$pivots - 1) {
            my $second =
                $pivots->[$j];

            next if !$second;

            my $first_distance =
                $second->{index}
                - $first->{index};

            next
                if $first_distance
                < $self->{min_pivot_distance};

            for my $k ($j + 1 .. $#$pivots) {
                my $third =
                    $pivots->[$k];

                next if !$third;

                my $second_distance =
                    $third->{index}
                    - $second->{index};

                next
                    if $second_distance
                    < $self->{min_touch_distance};

                my $line =
                    $self->_build_line(
                        type        => $type,
                        first       => $first,
                        second      => $second,
                        third       => $third,
                        pivots      => $all_pivots,
                        candles     => $candles,
                        atr         => $atr,
                        until_index => $until_index,
                    );

                next if !$line;
                next if !$line->{valid};

                push @lines,
                    $line;
            }
        }
    }

    @lines =
        sort {
               ($b->{score} // 0)
                    <=> ($a->{score} // 0)

            || ($b->{touches} // 0)
                    <=> ($a->{touches} // 0)

            || ($b->{third_index} // 0)
                    <=> ($a->{third_index} // 0)
        } @lines;

    return @lines;
}

sub _build_line {
    my ($self, %args) = @_;

    my $type =
        $args{type};

    my $first =
        $args{first};

    my $second =
        $args{second};

    my $third =
        $args{third};

    my $pivots =
        $args{pivots} || [];

    my $candles =
        $args{candles} || [];

    my $atr =
        $args{atr} || [];

    my $until_index =
        $args{until_index};

    return undef if !$first;
    return undef if !$second;
    return undef if !$third;

    return undef
        if $first->{index} >= $second->{index};

    return undef
        if $second->{index} >= $third->{index};

    # Calcula la mejor línea para los tres pivotes.
    my $fit =
        $self->_fit_line_from_pivots(
            pivots => [
                $first,
                $second,
                $third,
            ],
        );

    return undef
        if !$fit;

    my $slope =
        $fit->{slope};

    my $intercept =
        $fit->{intercept};

    # Una línea de soporte debe subir.
    return undef
        if $type eq 'BULLISH'
        && $slope <= 0;

    # Una línea de resistencia debe bajar.
    return undef
        if $type eq 'BEARISH'
        && $slope >= 0;

    my $line = {
        type      => $type,
        slope     => $slope,
        intercept => $intercept,

        start_index  => $first->{index},
        second_index => $second->{index},
        third_index  => $third->{index},

        confirmation_index =>
            $third->{index},

        start_price  => $first->{price},
        second_price => $second->{price},
        third_price  => $third->{price},

        first_pivot  => $first,
        second_pivot => $second,
        third_pivot  => $third,

        anchor_indices => [
            $first->{index},
            $second->{index},
            $third->{index},
        ],

        touch_indices => [
            $first->{index},
            $second->{index},
            $third->{index},
        ],

        touches => 3,

        fit_error =>
            $fit->{mean_error},

        max_fit_error =>
            $fit->{max_error},

        active      => 1,
        broken      => 0,
        break_index => undef,
        break_price => undef,

        valid  => 1,
        status => 'CONFIRMED',
        score  => 0,
    };

    # Verifica que cada uno de los tres pivotes esté suficientemente
    # cerca de la línea ajustada.
    for my $pivot (
        $first,
        $second,
        $third
    ) {
        my $line_price =
            $self->_line_value_at(
                $line,
                $pivot->{index}
            );

        my $atr_value =
            $self->_atr_at(
                $atr,
                $pivot->{index}
            );

        my $tolerance =
            $self->_tolerance(
                $atr_value,
                $line_price
            );

        my $distance =
            abs(
                $pivot->{price}
                - $line_price
            );

        return undef
            if $distance > $tolerance;
    }

    # La línea no debe atravesar de forma importante el precio
    # entre el primer y el tercer contacto.
    my $valid_segment =
        $self->_validate_segment(
            line       => $line,
            candles    => $candles,
            atr        => $atr,
            from_index => $first->{index},
            to_index   => $third->{index},
        );

    return undef
        if !$valid_segment;

    # Busca contactos adicionales después del tercer pivote.
    my @touches =
        $self->_find_additional_touches(
            line        => $line,
            pivots      => $pivots,
            atr         => $atr,
            until_index => $until_index,
            after_index => $third->{index},

            initial_touches => [
                $first->{index},
                $second->{index},
                $third->{index},
            ],
        );

    $line->{touch_indices} =
        \@touches;

    $line->{touches} =
        scalar(@touches);

    # Una ruptura solo puede evaluarse después de la confirmación
    # mediante el tercer contacto.
    my $break =
        $self->_find_confirmed_break(
            line        => $line,
            candles     => $candles,
            atr         => $atr,
            from_index  => $third->{index} + 1,
            until_index => $until_index,
        );

    if ($break) {
        $line->{active} =
            0;

        $line->{broken} =
            1;

        $line->{break_index} =
            $break->{index};

        $line->{break_price} =
            $break->{price};

        $line->{status} =
            'BROKEN';
    }
    else {
        $line->{active} =
            1;

        $line->{broken} =
            0;

        $line->{status} =
            'CONFIRMED';
    }

    $line->{score_components} =
        $self->_calculate_score_components(
            line        => $line,
            until_index => $until_index,
        );

    $line->{score} =
        $line->{score_components}{total};

    return $line;
}

sub _fit_line_from_pivots {
    my ($self, %args) = @_;

    my $pivots =
        $args{pivots} || [];

    return undef
        if @$pivots < 3;

    my $count = 0;

    my $sum_x  = 0;
    my $sum_y  = 0;
    my $sum_xy = 0;
    my $sum_x2 = 0;

    for my $pivot (@$pivots) {
        next if !$pivot;
        next if !defined $pivot->{index};
        next if !defined $pivot->{price};

        my $x =
            0 + $pivot->{index};

        my $y =
            0 + $pivot->{price};

        $count++;

        $sum_x  += $x;
        $sum_y  += $y;
        $sum_xy += $x * $y;
        $sum_x2 += $x * $x;
    }

    return undef
        if $count < 3;

    my $denominator =
          ($count * $sum_x2)
        - ($sum_x * $sum_x);

    return undef
        if abs($denominator) < 0.0000001;

    my $slope =
        (
              ($count * $sum_xy)
            - ($sum_x * $sum_y)
        )
        / $denominator;

    my $intercept =
        (
            $sum_y
            - ($slope * $sum_x)
        )
        / $count;

    my $total_error = 0;
    my $max_error   = 0;

    for my $pivot (@$pivots) {
        next if !$pivot;
        next if !defined $pivot->{index};
        next if !defined $pivot->{price};

        my $estimated =
              ($slope * $pivot->{index})
            + $intercept;

        my $error =
            abs(
                $pivot->{price}
                - $estimated
            );

        $total_error +=
            $error;

        $max_error =
            $error
            if $error > $max_error;
    }

    my $mean_error =
        $count > 0
        ? $total_error / $count
        : 0;

    return {
        slope      => $slope,
        intercept  => $intercept,
        mean_error => $mean_error,
        max_error  => $max_error,
    };
}

sub _validate_segment {
    my ($self, %args) = @_;

    my $line =
        $args{line};

    my $candles =
        $args{candles} || [];

    my $atr =
        $args{atr} || [];

    my $from =
        $args{from_index};

    my $to =
        $args{to_index};

    return 0 if !$line;

    for my $index ($from + 1 .. $to - 1) {
        my $candle =
            $candles->[$index];

        next if !$candle;

        my $line_price =
            $self->_line_value_at(
                $line,
                $index
            );

        my $atr_value =
            $self->_atr_at(
                $atr,
                $index
            );

        my $tolerance =
            $self->_tolerance(
                $atr_value,
                $line_price
            );

        if ($line->{type} eq 'BULLISH') {
            my $low =
                $candle->{low};

            next if !defined $low;

            return 0
                if $low
                < $line_price - $tolerance;
        }
        else {
            my $high =
                $candle->{high};

            next if !defined $high;

            return 0
                if $high
                > $line_price + $tolerance;
        }
    }

    return 1;
}

sub _find_additional_touches {
    my ($self, %args) = @_;

    my $line =
        $args{line};

    my $pivots =
        $args{pivots} || [];

    my $atr =
        $args{atr} || [];

    my $until_index =
        $args{until_index};

    my $after_index =
        defined $args{after_index}
        ? $args{after_index}
        : $line->{third_index};

    my @touches =
        ref($args{initial_touches}) eq 'ARRAY'
        ? @{$args{initial_touches}}
        : (
            $line->{start_index},
            $line->{second_index},
            $line->{third_index},
        );

    my $last_touch_index =
        @touches
        ? $touches[-1]
        : $after_index;

    for my $pivot (@$pivots) {
        next if !$pivot;
        next if !defined $pivot->{index};
        next if !defined $pivot->{price};
        next if !defined $pivot->{type};

        next
            if $pivot->{index}
            <= $after_index;

        next
            if $pivot->{index}
            > $until_index;

        next
            if (
                $pivot->{index}
                - $last_touch_index
            ) < $self->{min_touch_distance};

        if ($line->{type} eq 'BULLISH') {
            next
                if uc($pivot->{type}) ne 'LOW';
        }
        else {
            next
                if uc($pivot->{type}) ne 'HIGH';
        }

        my $line_price =
            $self->_line_value_at(
                $line,
                $pivot->{index}
            );

        my $atr_value =
            $self->_atr_at(
                $atr,
                $pivot->{index}
            );

        my $tolerance =
            $self->_tolerance(
                $atr_value,
                $line_price
            );

        my $distance =
            abs(
                $pivot->{price}
                - $line_price
            );

        next
            if $distance > $tolerance;

        push @touches,
            $pivot->{index};

        $last_touch_index =
            $pivot->{index};
    }

    my %seen;

    @touches =
        grep {
            defined $_
            && !$seen{$_}++
        }
        sort {
            $a <=> $b
        }
        @touches;

    return @touches;
}

sub _find_confirmed_break {
    my ($self, %args) = @_;

    my $line =
        $args{line};

    my $candles =
        $args{candles} || [];

    my $atr =
        $args{atr} || [];

    my $from_index =
        $args{from_index};

    my $until_index =
        $args{until_index};

    my $required =
        $self->{break_confirm_bars};

    my $consecutive = 0;
    my $first_break;

    for my $index ($from_index .. $until_index) {
        my $candle =
            $candles->[$index];

        next if !$candle;
        next if !defined $candle->{close};

        my $line_price =
            $self->_line_value_at(
                $line,
                $index
            );

        my $atr_value =
            $self->_atr_at(
                $atr,
                $index
            );

        my $break_tolerance =
              (
                  $atr_value > 0
                  ? $atr_value
                  : abs($line_price) * 0.0005
              )
            * $self->{break_atr_mult};

        my $is_break;

        if ($line->{type} eq 'BULLISH') {
            $is_break =
                $candle->{close}
                < $line_price - $break_tolerance;
        }
        else {
            $is_break =
                $candle->{close}
                > $line_price + $break_tolerance;
        }

        if ($is_break) {
            $consecutive++;

            $first_break //= {
                index => $index,
                price => $candle->{close},
            };

            if ($consecutive >= $required) {
                return $first_break;
            }
        }
        else {
            $consecutive = 0;
            $first_break = undef;
        }
    }

    return undef;
}

sub _calculate_score_components {
    my ($self, %args) = @_;

    my $line =
        $args{line};

    my $until_index =
        $args{until_index};

    my $touches =
        $line->{touches} // 2;

    # Máximo 40.
    my $touch_score =
        10 + (($touches - 2) * 15);

    $touch_score = 40
        if $touch_score > 40;

    # Máximo 20.
    my $status_score =
          $line->{status} eq 'CONFIRMED' ? 20
        : $line->{status} eq 'CANDIDATE' ? 8
        :                                 4;

    # Máximo 15.
    my $confirmation_index =
       $line->{confirmation_index}
    // $line->{third_index}
    // $line->{second_index};

    my $age =
        $until_index
        - $confirmation_index;

    $age = 0
        if $age < 0;

    my $recency_score =
        15 - int($age / 150);

    $recency_score = 0
        if $recency_score < 0;

    # Máximo 15.
    my $length =
        $confirmation_index
        - $line->{start_index};

    my $length_score =
          $length >= 100 ? 15
        : $length >= 50  ? 12
        : $length >= 20  ? 8
        :                  4;

    # Máximo 10.
    my $integrity_score =
        $line->{broken}
        ? 0
        : 10;

    my $total =
          $touch_score
        + $status_score
        + $recency_score
        + $length_score
        + $integrity_score;

    $total = 100
        if $total > 100;

    $total = 0
        if $total < 0;

    return {
        touches   => $touch_score,
        status    => $status_score,
        recency   => $recency_score,
        length    => $length_score,
        integrity => $integrity_score,
        structure => 0,

        total => $total,
    };
}

sub _select_visible_lines {
    my ($self, %args) = @_;

    my $lines =
        $args{lines} || [];

    my @selected;

    for my $type ('BULLISH', 'BEARISH') {

        # Únicamente líneas:
        # - de la dirección actual;
        # - confirmadas;
        # - no rotas;
        # - con mínimo 3 contactos.
        my @confirmed =
            grep {
                   ($_->{type} // '') eq $type
                && ($_->{status} // '') eq 'CONFIRMED'
                && !$_->{broken}
                && ($_->{touches} // 0)
                    >= $self->{confirmed_touches}
            } @$lines;

        @confirmed =
            sort {
                   ($b->{score} // 0) <=> ($a->{score} // 0)
                || ($b->{touches} // 0)
                    <=> ($a->{touches} // 0)
                || ($b->{second_index} // 0)
                    <=> ($a->{second_index} // 0)
            } @confirmed;

        my $maximum =
            $self->{max_lines_per_side}
            // 1;

        for my $line (@confirmed) {
            last
                if scalar(
                    grep {
                        ($_->{type} // '') eq $type
                    } @selected
                ) >= $maximum;

            push @selected, $line;
        }
    }

    return @selected;
}

sub _tolerance {
    my ($self, $atr_value, $reference_price) = @_;

    if (
        defined $atr_value
        && $atr_value > 0
    ) {
        return
            $atr_value
            * $self->{tolerance_atr_mult};
    }

    return
        abs($reference_price // 0)
        * 0.0008;
}

sub _line_value_at {
    my ($self, $line, $index) = @_;

    return undef if !$line;
    return undef if !defined $line->{slope};
    return undef if !defined $line->{intercept};
    return undef if !defined $index;

    return
          ($line->{slope} * $index)
        + $line->{intercept};
}

sub _atr_at {
    my ($self, $atr, $index) = @_;

    return 0
        if ref($atr) ne 'ARRAY';

    return 0
        if !defined $index;

    return 0
        if $index < 0;

    return 0
        if $index > $#$atr;

    return 0
        if !defined $atr->[$index];

    if (ref($atr->[$index]) eq 'HASH') {
        return
               $atr->[$index]{value}
            // $atr->[$index]{atr}
            // 0;
    }

    return
        $atr->[$index];
}

sub _empty_result {
    my ($self, %args) = @_;
    
    my $visible_start =
        defined $args{visible_start}
        ? $args{visible_start}
        : 0;

    my $visible_end =
        defined $args{visible_end}
        ? $args{visible_end}
        : 0;

    my $analysis_start =
        defined $args{analysis_start}
        ? $args{analysis_start}
        : $visible_start;

    my $pivots_used =
        defined $args{pivots_used}
        ? $args{pivots_used}
        : 0;

    return {
        trendlines => [],
        candidates => [],
        confirmed  => [],
        broken     => [],
        channels   => [],

        visible_start  => $visible_start,
        visible_end    => $visible_end,
        analysis_start => $analysis_start,

        audit => {
            pivots_used => $pivots_used,
            bullish_candidates => 0,
            bearish_candidates => 0,
            confirmed_lines    => 0,
            visible_lines      => 0,

            visible_start =>
                $visible_start,

            visible_end =>
                $visible_end,

            analysis_start =>
                $analysis_start,
        },
    };
}

1;