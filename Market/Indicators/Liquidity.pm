package Market::Indicators::Liquidity;

use strict;
use warnings;

sub new {
    my ($class, %args) = @_;

    my $self = {
        atr_mult         => $args{atr_mult}         // 4.0,
        minor_atr_mult   => $args{minor_atr_mult}   // 1.5,
        internal_zigzag_tf  => $args{internal_zigzag_tf}  // 60,
        internal_zigzag_prd => $args{internal_zigzag_prd} // 2,

        # Sensibilidad de la estructura SMC interna.
        # En el indicador TradingView se utiliza getCurrentStructure(5, ..., true).
        internal_smc_len    => $args{internal_smc_len}    // 5,
        # LuxAlgo usa 3 barras para confirmar EQH/EQL.
        equal_smc_len => $args{equal_smc_len} // 3,

        external_swing_len  => $args{external_swing_len}  // 150,
        volume_lookback      => $args{volume_lookback}      // 20,
        volume_mult          => $args{volume_mult}          // 2.8,
        volume_range_atr_min => $args{volume_range_atr_min} // 1.2,
                volume_react_mult    => $args{volume_react_mult}    // 1.5,
        min_swing_atr_mult   => $args{min_swing_atr_mult}   // 2.0,

        # ==========================================================
        # DIY SUPPLY / DEMAND
        # ==========================================================
                # Equivalente a swing_length = 10 del DIY.
        supply_demand_swing_length =>
            $args{supply_demand_swing_length} // 10,
        supply_demand_volume_lookback =>
            $args{supply_demand_volume_lookback} // 20,

        supply_demand_volume_mult =>
            $args{supply_demand_volume_mult} // 1.5,

        supply_demand_range_atr_min =>
            $args{supply_demand_range_atr_min} // 0.80,

        # El DIY utiliza ATR * (box_width / 10).
        # Con 2.5, el grosor resultante es ATR * 0.25.
        supply_demand_box_width =>
            $args{supply_demand_box_width} // 2.5,

        supply_demand_overlap_atr_mult =>
            $args{supply_demand_overlap_atr_mult} // 2.0,

        supply_demand_history =>
            $args{supply_demand_history} // 20,

        supply_demand_require_volume =>
            exists $args{supply_demand_require_volume}
                ? ($args{supply_demand_require_volume} ? 1 : 0)
                : 0,

        supply_demand_zones => [],

        volume_pivots => [],


        eq_tolerance     => $args{eq_tolerance}     // 0.10,
        confirm_bars     => $args{confirm_bars}     // 3,

        state            => 'BUSCANDO_MAXIMO',
        minor_state      => 'BUSCANDO_MAXIMO',

        candidate_high   => undef,
        candidate_low    => undef,

        minor_high       => undef,
        minor_low        => undef,

        pivots                    => [],
        minor_pivots              => [],
        volume_pivots             => [],
        volume_structural_pivots  => [],
        liquidity                 => [],
        events                    => [],
        equal_levels              => [],

        clean_volume_swings => [],

        structural_pivots_clean => [],
        
        # ZigZag interno MTF configurable.
        internal_structure      => [],

        # Pivotes internos SMC del timeframe activo.
        # Se utilizan exclusivamente para iBOS/iCHoCH.
        internal_smc_structure  => [],

        # Pivotes independientes para detectar Equal Highs y Equal Lows.
        equal_structure => [],

        # Estructura swing externa.
        external_structure      => [],

        internal_fibonacci      => [],
        external_fibonacci => undef,



        audit => {pivots => [],},


    };

    return bless $self, $class;
}

sub reset {
    my ($self) = @_;

    $self->{state}          = 'BUSCANDO_MAXIMO';
    $self->{minor_state}    = 'BUSCANDO_MAXIMO';

    $self->{candidate_high} = undef;
    $self->{candidate_low}  = undef;

    $self->{minor_high}     = undef;
    $self->{minor_low}      = undef;

    $self->{pivots}                   = [];
    $self->{minor_pivots}             = [];
    $self->{volume_pivots}            = [];
    $self->{volume_structural_pivots} = [];
    $self->{liquidity}                = [];
    $self->{events}                   = [];
    $self->{equal_levels}             = [];
    $self->{supply_demand_zones}      = [];

    $self->{clean_volume_swings} = [];
    $self->{structural_pivots_clean} = [];
    $self->{internal_structure}      = [];
    $self->{internal_smc_structure}  = [];
    $self->{equal_structure} = [];
    $self->{external_structure}      = [];
    $self->{internal_fibonacci}      = [];
     $self->{external_fibonacci} = undef;

    $self->{structural_pivots_clean} = [];
    $self->{audit}->{pivots} = [];
    $self->{audit}->{liquidity_classification} = {};
}

sub calculate_until {
    my ($self, $candles, $atr_values, $until_index) = @_;

    $self->reset();

    $until_index = $#$candles if !defined $until_index || $until_index > $#$candles;
    return {} if $until_index < 0;

    # ==============================================================
    # 1. ZIGZAG INTERNO MTF
    #
    # Continúa dependiendo del selector:
    # "ZZ Interno: 1 hora", 15 minutos, 4 horas, etc.
    #
    # Se utiliza para:
    # - dibujar el ZigZag interno;
    # - etiquetas internas HH/HL/LH/LL;
    # - Fibonacci interno.
    # ==============================================================
    $self->{internal_structure} = $self->_build_internal_zigzag_zzmtf(
        $candles,
        $until_index,
        $self->{internal_zigzag_tf},
        $self->{internal_zigzag_prd},
    );

    $self->{internal_fibonacci} = $self->_build_internal_fibonacci_zzmtf(
        $self->{internal_structure}
    );

    # ==============================================================
    # 2. ESTRUCTURA SMC INTERNA DEL TIMEFRAME ACTIVO
    #
    # No depende del selector del ZigZag interno.
    # Se calcula directamente sobre las velas actuales del gráfico.
    #
    # Se utiliza exclusivamente para:
    # - iBOS;
    # - iCHoCH;
    # - tendencia interna;
    # - posteriormente Order Blocks internos.
    # ==============================================================
    $self->{internal_smc_structure}
        = $self->_build_internal_smc_structure_luxalgo(
            $candles,
            $until_index,
            $self->{internal_smc_len},
        );
    # ==============================================================
    # 3. ESTRUCTURA INDEPENDIENTE PARA EQH / EQL
    #
    # LuxAlgo utiliza Confirmation Bars = 3.
    # Se calcula sobre la temporalidad activa del gráfico.
    # No depende del ZigZag interno MTF.
    # ==============================================================
    $self->{equal_structure}
        = $self->_build_equal_structure_luxalgo(
            $candles,
            $until_index,
            $self->{equal_smc_len},
        );

    # ==============================================================
    # 3. ESTRUCTURA SWING EXTERNA
    #
    # Se mantiene exactamente como está.
    # ==============================================================
    $self->{external_structure} = $self->_build_external_zigzag_chartprime(
        $candles,
        $until_index,
        $self->{external_swing_len},
    );
        # ==============================================================
    # FIBONACCI DEL ZIGZAG EXTERNO
    #
    # Se calcula únicamente sobre los dos últimos pivotes externos
    # disponibles hasta until_index.
    # ==============================================================
    $self->{external_fibonacci}
        = $self->_build_external_fibonacci(
            $self->{external_structure},
            $until_index,
        );

    $self->{minor_pivots} = $self->{internal_structure};
    $self->{pivots}      = $self->{external_structure};
    $self->{structural_pivots_clean} = $self->{external_structure};

    $self->_build_liquidity_from_external_structure();

    for my $i (0 .. $until_index) {
        my $bar = $candles->[$i];
        next if !$bar;
        $self->_update_liquidity_states($bar, $i);
    }

    $self->_detect_equal_levels($atr_values);

        $self->{supply_demand_zones}
        = $self->_build_supply_demand_zones(
            $candles,
            $atr_values,
            $until_index,
        );

    return {
        pivots              => $self->{pivots},
        structural_pivots   => $self->{external_structure},

        external_structure  => $self->{external_structure},

        # ZigZag interno MTF visible.
        internal_structure  => $self->{internal_structure},

        # Estructura interna del timeframe activo para iBOS/iCHoCH.
        internal_smc_structure => $self->{internal_smc_structure},
        equal_structure => $self->{equal_structure},

        raw_structural_pivots => $self->{pivots},
        raw_minor_pivots      => $self->{minor_pivots},
        minor_pivots          => $self->{internal_structure},

        volume_pivots       => $self->{volume_pivots},
        liquidity           => $self->{liquidity},
        events              => $self->{events},
        equal_levels        => $self->{equal_levels},
        clean_volume_swings => $self->{clean_volume_swings},
        audit               => $self->{audit},
                internal_fibonacci =>
            $self->{internal_fibonacci},

        external_fibonacci =>
            $self->{external_fibonacci},

        supply_demand_zones =>
            $self->{supply_demand_zones},
    };
}

sub process_bar {
    my ($self, $candles, $atr_values, $i) = @_;

    my $bar = $candles->[$i];
    return if !$bar;

    my $atr = $atr_values->[$i] // 0;
    return if $atr <= 0;

    $self->_process_minor_pivot($candles, $bar, $atr, $i);
    $self->_process_structural_pivot($candles, $bar, $atr, $i);
    $self->_update_liquidity_states($bar, $i);
}

sub _bucket_epoch_for_tf {
    my ($self, $epoch, $tf) = @_;

    return undef if !defined $epoch;

    if ($tf eq 'D') {
        return int($epoch / 86400) * 86400;
    }

    if ($tf eq 'W') {
        return int($epoch / (86400 * 7)) * (86400 * 7);
    }

    my $minutes = $tf + 0;
    $minutes = 60 if $minutes <= 0;

    my $seconds = $minutes * 60;
    return int($epoch / $seconds) * $seconds;
}

sub _highest_index {
    my ($self, $candles, $from, $to) = @_;

    my $best_i = $from;
    my $best_v = $candles->[$from]{high};

    for my $i ($from .. $to) {
        next if !$candles->[$i];
        if ($candles->[$i]{high} >= $best_v) {
            $best_v = $candles->[$i]{high};
            $best_i = $i;
        }
    }

    return $best_i;
}

sub _lowest_index {
    my ($self, $candles, $from, $to) = @_;

    my $best_i = $from;
    my $best_v = $candles->[$from]{low};

    for my $i ($from .. $to) {
        next if !$candles->[$i];
        if ($candles->[$i]{low} <= $best_v) {
            $best_v = $candles->[$i]{low};
            $best_i = $i;
        }
    }

    return $best_i;
}

sub _zz_add_or_update {
    my ($self, $zz, $pivot) = @_;

    return if !$pivot;

    my $last = $zz->[-1];

    if (!$last) {
        push @$zz, $pivot;
        return;
    }

    if ($last->{type} eq $pivot->{type}) {
        if (
            ($pivot->{type} eq 'HIGH' && $pivot->{price} > $last->{price})
            ||
            ($pivot->{type} eq 'LOW'  && $pivot->{price} < $last->{price})
        ) {
            $zz->[-1] = $pivot;
        }
        return;
    }

    push @$zz, $pivot;
}

sub _build_internal_smc_structure_luxalgo {
    my ($self, $candles, $until_index, $size) = @_;

    $size //= 5;

    my @pivots;

    return \@pivots if !$candles;
    return \@pivots if ref($candles) ne 'ARRAY';
    return \@pivots if $until_index < $size;
    return \@pivots if $size < 1;

    # En el indicador:
    #
    # 0 = bearish leg
    # 1 = bullish leg
    #
    # Empieza en 0 de la misma forma que:
    # var int legState = 0
    my $leg_state = 0;

    for my $i ($size .. $until_index) {

        # La vela candidata está "size" posiciones atrás.
        #
        # Para size=5 y vela actual i=100:
        # candidato = 95
        #
        # Esto replica:
        # high[size]
        # low[size]
        my $candidate_i = $i - $size;
        my $candidate   = $candles->[$candidate_i];

        next if !$candidate;
        next if !defined $candidate->{high};
        next if !defined $candidate->{low};

        # El indicador compara la vela candidata contra las
        # siguientes "size" velas ya conocidas:
        #
        # high[size] > ta.highest(size)
        # low[size]  < ta.lowest(size)
        #
        # En el momento i todas estas velas ya existen.
        my $comparison_from = $candidate_i + 1;
        my $comparison_to   = $i;

        my $highest_after;
        my $lowest_after;

        for my $j ($comparison_from .. $comparison_to) {

            my $bar = $candles->[$j];
            next if !$bar;

            if (defined $bar->{high}) {
                $highest_after = $bar->{high}
                    if !defined $highest_after
                    || $bar->{high} > $highest_after;
            }

            if (defined $bar->{low}) {
                $lowest_after = $bar->{low}
                    if !defined $lowest_after
                    || $bar->{low} < $lowest_after;
            }
        }

        next if !defined $highest_after;
        next if !defined $lowest_after;

        my $new_high = $candidate->{high} > $highest_after
            ? 1
            : 0;

        my $new_low = $candidate->{low} < $lowest_after
            ? 1
            : 0;

        my $previous_leg = $leg_state;

        # Equivalente a la prioridad del Pine Script:
        #
        # if newHigh
        #     legState := BEARISH_LEG
        # else if newLow
        #     legState := BULLISH_LEG
        if ($new_high) {
            $leg_state = 0;
        }
        elsif ($new_low) {
            $leg_state = 1;
        }

        # Solo existe un nuevo pivote cuando cambia la pierna.
        next if $leg_state == $previous_leg;

        my ($type, $price);

        if ($leg_state == 1) {
            # Inicio de pierna alcista:
            # el punto confirmado es un LOW.
            $type  = 'LOW';
            $price = $candidate->{low};
        }
        else {
            # Inicio de pierna bajista:
            # el punto confirmado es un HIGH.
            $type  = 'HIGH';
            $price = $candidate->{high};
        }

        push @pivots, {
            type  => $type,
            price => $price,

            # IMPORTANTE:
            #
            # index es el instante de confirmación.
            # El nivel no puede estar activo antes de esta vela.
            #
            # Esto mantiene Replay causal y evita utilizar
            # información futura.
            index => $i,

            # display_index es la vela real donde ocurrió el extremo.
            # La línea del iBOS/iCHoCH debe comenzar aquí.
            display_index => $candidate_i,

            confirmed_index => $i,

            source         => 'INTERNAL_SMC_LUXALGO',
            tier           => 'internal',
            structure_mode => 'internal',
            size           => $size,

            timestamp => $candidate->{time},
        };
    }

    return \@pivots;
}

sub _build_equal_structure_luxalgo {
    my ($self, $candles, $until_index, $size) = @_;

    $size //= 3;

    my @pivots;

    return \@pivots if !$candles;
    return \@pivots if ref($candles) ne 'ARRAY';
    return \@pivots if $size < 1;
    return \@pivots if $until_index < $size;

    my $leg_state = 0;

    for my $i ($size .. $until_index) {

        my $candidate_i = $i - $size;
        my $candidate   = $candles->[$candidate_i];

        next if !$candidate;
        next if !defined $candidate->{high};
        next if !defined $candidate->{low};

        my $highest_after;
        my $lowest_after;

        for my $j ($candidate_i + 1 .. $i) {

            my $bar = $candles->[$j];
            next if !$bar;

            if (defined $bar->{high}) {
                $highest_after = $bar->{high}
                    if !defined $highest_after
                    || $bar->{high} > $highest_after;
            }

            if (defined $bar->{low}) {
                $lowest_after = $bar->{low}
                    if !defined $lowest_after
                    || $bar->{low} < $lowest_after;
            }
        }

        next if !defined $highest_after;
        next if !defined $lowest_after;

        my $new_high =
            $candidate->{high} > $highest_after ? 1 : 0;

        my $new_low =
            $candidate->{low} < $lowest_after ? 1 : 0;

        my $previous_leg = $leg_state;

        if ($new_high) {
            $leg_state = 0;
        }
        elsif ($new_low) {
            $leg_state = 1;
        }

        next if $leg_state == $previous_leg;

        my ($type, $price);

        if ($leg_state == 1) {
            $type  = 'LOW';
            $price = $candidate->{low};
        }
        else {
            $type  = 'HIGH';
            $price = $candidate->{high};
        }

        push @pivots, {
            type            => $type,
            price           => $price,

            # Momento en que el pivote queda confirmado.
            index           => $i,

            # Lugar real del extremo.
            display_index   => $candidate_i,
            confirmed_index => $i,

            source          => 'EQUAL_STRUCTURE_LUXALGO',
            tier            => 'equal',
            structure_mode  => 'equal',
            size            => $size,
            timestamp       => $candidate->{time},
        };
    }

    return \@pivots;
}


sub _build_internal_zigzag_zzmtf {
    my ($self, $candles, $until_index, $tf, $prd) = @_;

    $tf  //= 60;
    $prd //= 2;

    my @zigzag;
    my @newbar_indices;

    my $prev_bucket;
    my $dir = 0;

    for my $i (0 .. $until_index) {
        my $bar = $candles->[$i];
        next if !$bar;

        my $bucket = $self->_bucket_epoch_for_tf($bar->{epoch}, $tf);

        my $newbar = 0;
        if (!defined $prev_bucket || $bucket != $prev_bucket) {
            $newbar = 1;
            push @newbar_indices, $i;
            $prev_bucket = $bucket;
        }

        my $bi;
        if (@newbar_indices >= $prd) {
            $bi = $newbar_indices[-$prd];
        } else {
            $bi = 0;
        }

        my $len_from = $bi;
        my $len_to   = $i;

        my $hi_i = $self->_highest_index($candles, $len_from, $len_to);
        my $lo_i = $self->_lowest_index($candles,  $len_from, $len_to);

        my $ph = ($hi_i == $i) ? $bar->{high} : undef;
        my $pl = ($lo_i == $i) ? $bar->{low}  : undef;

        my $old_dir = $dir;

        if (defined $ph && !defined $pl) {
            $dir = 1;
        }
        elsif (defined $pl && !defined $ph) {
            $dir = -1;
        }

        next if !defined $ph && !defined $pl;
        next if $dir == 0;

        my $value = $dir == 1 ? $ph : $pl;

        my $pivot = {
            type           => $dir == 1 ? 'HIGH' : 'LOW',
            index          => $i,
            price          => $value,
            source         => 'ZZMTF',
            tier           => 'internal',
            structure_mode => 'internal',
            tf             => $tf,
            prd            => $prd,
            timestamp      => $bar->{time},
        };

        if (!@zigzag) {
            push @zigzag, $pivot;
            next;
        }

        my $last = $zigzag[-1];

        my $dir_changed = ($dir != $old_dir) ? 1 : 0;

        if ($dir_changed) {
            push @zigzag, $pivot;
        }
        else {
            if (
                ($dir == 1  && $pivot->{price} > $last->{price})
                ||
                ($dir == -1 && $pivot->{price} < $last->{price})
            ) {
                $zigzag[-1] = $pivot;
            }
        }
    }

    return \@zigzag;
}
sub _build_internal_fibonacci_zzmtf {
    my ($self, $internal_structure) = @_;

    my @levels;
    return \@levels if !$internal_structure || @$internal_structure < 2;

    my $a = $internal_structure->[-2];
    my $b = $internal_structure->[-1];

    return \@levels if !$a || !$b;
    return \@levels if !defined $a->{price} || !defined $b->{price};

    my @ratios = (
        0.000,
        0.236,
        0.382,
        0.500,
        0.618,
        0.786,
        1.000,
    );

    my $diff = $a->{price} - $b->{price};

    for my $ratio (@ratios) {
        push @levels, {
            ratio       => $ratio,
            price       => $b->{price} + ($diff * $ratio),
            from_index  => $a->{index},
            to_index    => $b->{index},
            from_price  => $a->{price},
            to_price    => $b->{price},
            source      => 'ZZMTF_Fibonacci',
            tier        => 'internal',
        };
    }

    return \@levels;
}

# ==============================================================
# FIBONACCI DEL ÚLTIMO TRAMO DEL ZIGZAG EXTERNO
#
# Utiliza exclusivamente los dos últimos pivotes externos:
#
# LOW  -> HIGH: retroceso desde HIGH hacia LOW.
# HIGH -> LOW : retroceso desde LOW hacia HIGH.
#
# No modifica el ZigZag ni genera pivotes nuevos.
# ==============================================================
sub _build_external_fibonacci {
    my (
        $self,
        $external_structure,
        $until_index,
    ) = @_;

    return undef
        if !$external_structure
        || ref($external_structure) ne 'ARRAY'
        || @{$external_structure} < 2;

    return undef
        if !defined $until_index
        || $until_index < 0;

    # Conservar únicamente pivotes válidos que ya pertenecen
    # al rango permitido del cálculo actual.
    my @pivots = grep {
           $_
        && ref($_) eq 'HASH'
        && defined $_->{index}
        && defined $_->{price}
        && defined $_->{type}
        && $_->{index} <= $until_index
        && (
               $_->{type} eq 'HIGH'
            || $_->{type} eq 'LOW'
        )
    } @{$external_structure};

    return undef
        if @pivots < 2;

    # La estructura externa ya viene cronológica, pero ordenar
    # aquí evita depender de ese supuesto.
    @pivots = sort {
           $a->{index}
        <=>
           $b->{index}
    } @pivots;

    my $from = $pivots[-2];
    my $to   = $pivots[-1];

    return undef
        if !$from
        || !$to;

    # Un tramo válido debe alternar HIGH/LOW.
    return undef
        if ($from->{type} // '')
        eq
        ($to->{type} // '');

    return undef
        if $to->{index} <= $from->{index};

    my $from_price =
        $from->{price};

    my $to_price =
        $to->{price};

    return undef
        if !defined $from_price
        || !defined $to_price;

    my $range =
        abs(
            $to_price
            -
            $from_price
        );

    return undef
        if $range <= 0;

    my $direction;

    if (
        $from->{type} eq 'LOW'
        &&
        $to->{type} eq 'HIGH'
    ) {
        $direction = 'UP';
    }
    elsif (
        $from->{type} eq 'HIGH'
        &&
        $to->{type} eq 'LOW'
    ) {
        $direction = 'DOWN';
    }
    else {
        return undef;
    }

    my @level_definitions = (
        {
            ratio => 0.382,
            color => '#81c784',
        },
        {
            ratio => 0.500,
            color => '#26a69a',
        },
        {
            ratio => 0.618,
            color => '#2e7d32',
        },
        {
            ratio => 0.705,
            color => '#ef5350',
        },
        {
            ratio => 0.786,
            color => '#42a5f5',
        },
    );

    my @levels;

    for my $definition (@level_definitions) {
        my $ratio =
            $definition->{ratio};

        my $price;

        if ($direction eq 'UP') {
            # Último impulso:
            #
            # LOW -> HIGH
            #
            # El retroceso se mide desde el HIGH hacia el LOW:
            #
            # 0.000 = HIGH
            # 1.000 = LOW
            $price =
                  $to_price
                - ($range * $ratio);
        }
        else {
            # Último impulso:
            #
            # HIGH -> LOW
            #
            # El retroceso se mide desde el LOW hacia el HIGH:
            #
            # 0.000 = LOW
            # 1.000 = HIGH
            $price =
                  $to_price
                + ($range * $ratio);
        }

        push @levels, {
            ratio => $ratio,
            price => $price,
            color => $definition->{color},

            from_index => $from->{index},
            to_index   => $to->{index},

            direction => $direction,

            source => 'EXTERNAL_ZIGZAG_FIBONACCI',
        };
    }

    return {
        source =>
            'EXTERNAL_ZIGZAG_FIBONACCI',

        direction =>
            $direction,

        from_index =>
            $from->{index},

        to_index =>
            $to->{index},

        from_price =>
            $from_price,

        to_price =>
            $to_price,

        from_type =>
            $from->{type},

        to_type =>
            $to->{type},

        # Los niveles se proyectan hasta la última vela
        # actualmente permitida.
        projection_end_index =>
            $until_index,

        levels =>
            \@levels,
    };

}

sub _build_external_zigzag_chartprime {
    my ($self, $candles, $until_index, $swing_len) = @_;

    $swing_len //= 150;

    my @zigzag;

    my $is_bullish;
    my $prev_is_bullish;

    my ($bar_index_low,  $price_low);
    my ($bar_index_high, $price_high);

    my ($last_price_low, $last_price_high);

    for my $i (1 .. $until_index) {
        my $bar  = $candles->[$i];
        my $prev = $candles->[$i - 1];

        next if !$bar || !$prev;

        my $from_now = $i - $swing_len + 1;
        $from_now = 0 if $from_now < 0;

        my $from_prev = ($i - 1) - $swing_len + 1;
        $from_prev = 0 if $from_prev < 0;

        my $swing_high_i      = $self->_highest_index($candles, $from_now,  $i);
        my $swing_low_i       = $self->_lowest_index($candles,  $from_now,  $i);
        my $prev_swing_high_i = $self->_highest_index($candles, $from_prev, $i - 1);
        my $prev_swing_low_i  = $self->_lowest_index($candles,  $from_prev, $i - 1);

        my $swing_high_price = $candles->[$swing_high_i]{high};
        my $swing_low_price  = $candles->[$swing_low_i]{low};

        $prev_is_bullish = $is_bullish;

        if ($swing_high_i == $i) {
            $is_bullish = 1;
        }

        if ($swing_low_i == $i) {
            $is_bullish = 0;
        }

        if (
            $prev_swing_high_i == $i - 1
            && $bar->{high} < $swing_high_price
        ) {
            $bar_index_high = $i - 1;
            $price_high     = $prev->{high};
        }

        if (
            $prev_swing_low_i == $i - 1
            && $bar->{low} > $swing_low_price
        ) {
            $bar_index_low = $i - 1;
            $price_low     = $prev->{low};
        }

        next if !defined $is_bullish;

        if (
            defined $prev_is_bullish
            && $prev_is_bullish != $is_bullish
            && $is_bullish
            && defined $bar_index_low
            && defined $price_low
            && defined $bar_index_high
            && defined $price_high
        ) {
            push @zigzag, {
                type           => 'LOW',
                index          => $bar_index_low,
                price          => $price_low,
                source         => 'ChartPrimeLow',
                tier           => 'external',
                structure_mode => 'external',
                swing_len      => $swing_len,
                timestamp      => $candles->[$bar_index_low]{time},
            };

            push @zigzag, {
                type           => 'HIGH',
                index          => $bar_index_high,
                price          => $price_high,
                source         => 'ChartPrimeHigh',
                tier           => 'external',
                structure_mode => 'external',
                swing_len      => $swing_len,
                timestamp      => $candles->[$bar_index_high]{time},
            };
        }

        if (
            defined $prev_is_bullish
            && $prev_is_bullish != $is_bullish
            && !$is_bullish
            && defined $bar_index_high
            && defined $price_high
            && defined $bar_index_low
            && defined $price_low
        ) {
            push @zigzag, {
                type           => 'HIGH',
                index          => $bar_index_high,
                price          => $price_high,
                source         => 'ChartPrimeHigh',
                tier           => 'external',
                structure_mode => 'external',
                swing_len      => $swing_len,
                timestamp      => $candles->[$bar_index_high]{time},
            };

            push @zigzag, {
                type           => 'LOW',
                index          => $bar_index_low,
                price          => $price_low,
                source         => 'ChartPrimeLow',
                tier           => 'external',
                structure_mode => 'external',
                swing_len      => $swing_len,
                timestamp      => $candles->[$bar_index_low]{time},
            };
        }

        # Equivalente a line.set_xy2 cuando la dirección sigue alcista
        if (
            $is_bullish
            && defined $bar_index_high
            && defined $price_high
            && @zigzag
            && $zigzag[-1]{type} eq 'HIGH'
        ) {
            $zigzag[-1] = {
                type           => 'HIGH',
                index          => $bar_index_high,
                price          => $price_high,
                source         => 'ChartPrimeActiveHigh',
                tier           => 'external',
                structure_mode => 'external',
                swing_len      => $swing_len,
                timestamp      => $candles->[$bar_index_high]{time},
            };
        }

        # Equivalente a line.set_xy2 cuando la dirección sigue bajista
        if (
            !$is_bullish
            && defined $bar_index_low
            && defined $price_low
            && @zigzag
            && $zigzag[-1]{type} eq 'LOW'
        ) {
            $zigzag[-1] = {
                type           => 'LOW',
                index          => $bar_index_low,
                price          => $price_low,
                source         => 'ChartPrimeActiveLow',
                tier           => 'external',
                structure_mode => 'external',
                swing_len      => $swing_len,
                timestamp      => $candles->[$bar_index_low]{time},
            };
        }
    }

    my @clean;

    for my $p (@zigzag) {
        next if !$p;
        next if !defined $p->{index};
        next if !defined $p->{type};
        next if !defined $p->{price};

        if (@clean && $clean[-1]{index} == $p->{index} && $clean[-1]{type} eq $p->{type}) {
            $clean[-1] = $p;
            next;
        }

        if (@clean && $clean[-1]{type} eq $p->{type}) {
            if (
                ($p->{type} eq 'HIGH' && $p->{price} > $clean[-1]{price})
                ||
                ($p->{type} eq 'LOW' && $p->{price} < $clean[-1]{price})
            ) {
                $clean[-1] = $p;
            }
            next;
        }

        push @clean, $p;
    }

    return \@clean;
}

sub _build_liquidity_from_external_structure {
    my ($self) = @_;

    $self->{liquidity} = [];

    for my $p (@{$self->{external_structure} || []}) {
        next if !$p;
        next if !defined $p->{type};
        next if !defined $p->{price};
        next if !defined $p->{index};

        if ($p->{type} eq 'HIGH') {
            push @{$self->{liquidity}}, {
                type           => 'BSL',
                state          => 'Detected',
                index          => $p->{index},
                created_index  => $p->{index},
                swept_index    => undef,
                resolved_index => undef,
                price          => $p->{price},
                source         => 'ExternalZigZagHigh',
                tier           => 'external',
                classification => undef,
                outside_count  => 0,
            };
        }
        elsif ($p->{type} eq 'LOW') {
            push @{$self->{liquidity}}, {
                type           => 'SSL',
                state          => 'Detected',
                index          => $p->{index},
                created_index  => $p->{index},
                swept_index    => undef,
                resolved_index => undef,
                price          => $p->{price},
                source         => 'ExternalZigZagLow',
                tier           => 'external',
                classification => undef,
                outside_count  => 0,
            };
        }
    }
}



sub _avg_volume {
    my ($self, $candles, $i) = @_;

    my $lookback = $self->{volume_lookback} // 20;
    my $start = $i - $lookback;
    $start = 0 if $start < 0;

    my $sum = 0;
    my $count = 0;

    for my $j ($start .. $i - 1) {
        next if !defined $candles->[$j];
        $sum += $candles->[$j]{volume} // 0;
        $count++;
    }

    return 0 if $count == 0;
    return $sum / $count;
}

sub _is_volume_structural {
    my ($self, $candles, $atr, $pivot) = @_;

    return 0 if !$pivot;
    return 0 if !defined $pivot->{index};

    my $i = $pivot->{index};
    my $bar = $candles->[$i];
    return 0 if !$bar;

    my $avg_vol = $self->_avg_volume($candles, $i);
    return 0 if $avg_vol <= 0;

    my $volume = $bar->{volume} // 0;
    my $relative_volume = $volume / $avg_vol;

    my $range = ($bar->{high} // 0) - ($bar->{low} // 0);
    my $range_atr = $atr > 0 ? $range / $atr : 0;

    $pivot->{volume}          = $volume;
    $pivot->{avg_volume}      = $avg_vol;
    $pivot->{relative_volume} = $relative_volume;
    $pivot->{range_atr}       = $range_atr;

    return 1
        if $relative_volume >= ($self->{volume_mult} // 2.5)
        && $range_atr >= ($self->{volume_range_atr_min} // 1.2);

    return 0;
}

sub _already_structural_pivot {
    my ($self, $pivot) = @_;

    return 1 if !$pivot;

    for my $p (@{$self->{pivots}}) {
        return 1
            if $p->{index} == $pivot->{index}
            && $p->{type}  eq $pivot->{type};
    }

    return 0;
}

sub _promote_minor_to_structural {
    my ($self, $pivot) = @_;

    return if !$pivot;

    my %copy = %$pivot;

    $copy{tier}               = 'volume';
    $copy{source}             = 'VolumeCandidatePivot';
    $copy{promoted_by_volume} = 1;

    push @{$self->{volume_pivots}}, \%copy;
}



sub _clean_zigzag_sequence {
    my ($self, $pivots, $target_ref, $mode) = @_;

    my @candidates = sort {
        $a->{index} <=> $b->{index}
            ||
        ($b->{price} // 0) <=> ($a->{price} // 0)
    } grep {
        defined $_
        && defined $_->{index}
        && defined $_->{type}
        && defined $_->{price}
    } @$pivots;

    my @clean;

    for my $p (@candidates) {
        my %copy = %$p;
        $copy{structure_mode} = $mode;

        my $last = $clean[-1];

        if (!$last) {
            push @clean, \%copy;
            next;
        }

        if ($last->{type} eq $copy{type}) {
            if (
                ($copy{type} eq 'HIGH' && $copy{price} > $last->{price})
                ||
                ($copy{type} eq 'LOW'  && $copy{price} < $last->{price})
            ) {
                $clean[-1] = \%copy;
            }
            next;
        }

        push @clean, \%copy;


        push @{$self->{audit}->{pivots}}, {

            index => $copy{index},

            type  => $copy{type},

            price => $copy{price},

            structure => $mode,

            source => $copy{source} // 'ATR',

            timestamp => $copy{timestamp},

        };

    }

    $$target_ref = \@clean;
}



sub _clean_structural_sequence {
    my ($self) = @_;

    my @candidates = (
        @{$self->{pivots} || []},
        @{$self->{volume_pivots} || []},
    );

    @candidates = sort {
        $a->{index} <=> $b->{index}
            ||
        ($b->{price} // 0) <=> ($a->{price} // 0)
    } @candidates;

    my @clean;

    for my $p (@candidates) {
        next if !$p;
        next if !defined $p->{index};
        next if !defined $p->{type};
        next if !defined $p->{price};

        my %copy = %$p;
        $copy{tier} //= 'structural';

        my $last = $clean[-1];

        if (!$last) {
            push @clean, \%copy;
            next;
        }

        if ($last->{index} == $copy{index}) {
            if ($last->{type} eq $copy{type}) {
                if (
                    ($copy{type} eq 'HIGH' && $copy{price} > $last->{price})
                    ||
                    ($copy{type} eq 'LOW'  && $copy{price} < $last->{price})
                ) {
                    $clean[-1] = \%copy;
                }
            }
            next;
        }

        if ($last->{type} eq $copy{type}) {

            if (
                ($copy{type} eq 'HIGH' && $copy{price} > $last->{price})
                ||
                ($copy{type} eq 'LOW'  && $copy{price} < $last->{price})
            ) {
                $clean[-1] = \%copy;
            }

            next;
        }

        push @clean, \%copy;
    }

    $self->{structural_pivots_clean} = \@clean;
}
sub _process_minor_pivot {
    my ($self, $candles, $bar, $atr, $i) = @_;

    my $threshold = $atr * $self->{minor_atr_mult};

    my $high  = $bar->{high};
    my $low   = $bar->{low};
    my $close = $bar->{close};

    if ($self->{minor_state} eq 'BUSCANDO_MAXIMO') {

        if (!defined $self->{minor_high} || $high > $self->{minor_high}->{price}) {
            $self->{minor_high} = {
                type  => 'HIGH',
                index => $i,
                price => $high,
                atr   => $atr,
                tier  => 'minor',
            };
        }

        if (defined $self->{minor_high} && ($self->{minor_high}->{price} - $close) >= $threshold) {
            push @{$self->{minor_pivots}}, $self->{minor_high};

            if ($self->_is_volume_structural($candles, $atr, $self->{minor_high})) {
                $self->_promote_minor_to_structural($self->{minor_high});
            }

            $self->{minor_low} = {
                type  => 'LOW',
                index => $i,
                price => $low,
                atr   => $atr,
                tier  => 'minor',
            };

            $self->{minor_high}  = undef;
            $self->{minor_state} = 'BUSCANDO_MINIMO';
        }

    } elsif ($self->{minor_state} eq 'BUSCANDO_MINIMO') {

        if (!defined $self->{minor_low} || $low < $self->{minor_low}->{price}) {
            $self->{minor_low} = {
                type  => 'LOW',
                index => $i,
                price => $low,
                atr   => $atr,
                tier  => 'minor',
            };
        }

        if (defined $self->{minor_low} && ($close - $self->{minor_low}->{price}) >= $threshold) {
            push @{$self->{minor_pivots}}, $self->{minor_low};

            if ($self->_is_volume_structural($candles, $atr, $self->{minor_low})) {
                $self->_promote_minor_to_structural($self->{minor_low});
            }

            $self->{minor_high} = {
                type  => 'HIGH',
                index => $i,
                price => $high,
                atr   => $atr,
                tier  => 'minor',
            };

            $self->{minor_low}   = undef;
            $self->{minor_state} = 'BUSCANDO_MAXIMO';
        }
    }
}



sub _process_structural_pivot {
    my ($self, $candles, $bar, $atr, $i) = @_;

    my $threshold = $atr * $self->{atr_mult};

    my $high  = $bar->{high};
    my $low   = $bar->{low};
    my $close = $bar->{close};

    if ($self->{state} eq 'BUSCANDO_MAXIMO') {

        if (!defined $self->{candidate_high} || $high > $self->{candidate_high}->{price}) {
            $self->{candidate_high} = {
                type  => 'HIGH',
                index => $i,
                price => $high,
                atr   => $atr,
                tier  => 'structural',
            };
        }

        if (defined $self->{candidate_high} && ($self->{candidate_high}->{price} - $close) >= $threshold) {
            push @{$self->{pivots}}, $self->{candidate_high};

            push @{$self->{liquidity}}, {
                type           => 'BSL',
                state          => 'Detected',
                index          => $self->{candidate_high}->{index},
                price          => $self->{candidate_high}->{price},
                source         => 'StructuralPivotHigh',
                tier           => 'structural',
                created_index  => $self->{candidate_high}->{index},
                swept_index    => undef,
                resolved_index => undef,
                classification => undef,
                outside_count  => 0,
            };

            $self->{candidate_low} = {
                type  => 'LOW',
                index => $i,
                price => $low,
                atr   => $atr,
                tier  => 'structural',
            };

            $self->{candidate_high} = undef;
            $self->{state} = 'BUSCANDO_MINIMO';
        }
    }

    elsif ($self->{state} eq 'BUSCANDO_MINIMO') {

        if (!defined $self->{candidate_low} || $low < $self->{candidate_low}->{price}) {
            $self->{candidate_low} = {
                type  => 'LOW',
                index => $i,
                price => $low,
                atr   => $atr,
                tier  => 'structural',
            };
        }

        if (defined $self->{candidate_low} && ($close - $self->{candidate_low}->{price}) >= $threshold) {
            push @{$self->{pivots}}, $self->{candidate_low};

            push @{$self->{liquidity}}, {
                type           => 'SSL',
                state          => 'Detected',
                index          => $self->{candidate_low}->{index},
                created_index  => $self->{candidate_low}->{index},
                swept_index    => undef,
                resolved_index => undef,
                price          => $self->{candidate_low}->{price},
                source         => 'StructuralPivotLow',
                tier           => 'structural',
                classification => undef,
                outside_count  => 0,
            };

            $self->{candidate_high} = {
                type  => 'HIGH',
                index => $i,
                price => $high,
                atr   => $atr,
                tier  => 'structural',
            };

            $self->{candidate_low} = undef;
            $self->{state} = 'BUSCANDO_MAXIMO';
        }
    }
}


sub _detect_equal_levels {
    my ($self, $atr_values) = @_;

    $self->{equal_levels} = [];

    my $pivots = $self->{equal_structure} || [];

    return if ref($pivots) ne 'ARRAY';
    return if !@$pivots;

    my $last_equal_high;
    my $last_equal_low;

    for my $pivot (@$pivots) {

        next if !$pivot;
        next if !defined $pivot->{type};
        next if !defined $pivot->{price};
        next if !defined $pivot->{index};

        my $atr = 0;

        if (
            $atr_values
            && ref($atr_values) eq 'ARRAY'
            && defined $atr_values->[$pivot->{index}]
        ) {
            $atr = $atr_values->[$pivot->{index}];
        }

        next if !defined $atr || $atr <= 0;

        my $tolerance =
            $atr * ($self->{eq_tolerance} // 0.10);

        if ($pivot->{type} eq 'HIGH') {

            if ($last_equal_high) {

                my $difference = abs(
                    $last_equal_high->{price}
                    - $pivot->{price}
                );

                if ($difference < $tolerance) {

                    push @{$self->{equal_levels}}, {
                        type  => 'EQH',
                        tier  => 'equal',
                        mode  => 'equal',

                        index1 => defined $last_equal_high->{display_index}
                            ? $last_equal_high->{display_index}
                            : $last_equal_high->{index},

                        index2 => defined $pivot->{display_index}
                            ? $pivot->{display_index}
                            : $pivot->{index},

                        confirmed_index1 =>
                            $last_equal_high->{index},

                        confirmed_index2 =>
                            $pivot->{index},

                        price1 => $last_equal_high->{price},
                        price2 => $pivot->{price},

                        # LuxAlgo dibuja la línea sobre el nuevo nivel.
                        price => $pivot->{price},

                        tolerance => $tolerance,
                        difference => $difference,

                        source => 'EqualHighLuxAlgo',
                    };
                }
            }

            # Igual que equalHigh.currentLevel:
            # siempre actualizar al último HIGH confirmado.
            $last_equal_high = $pivot;
        }

        elsif ($pivot->{type} eq 'LOW') {

            if ($last_equal_low) {

                my $difference = abs(
                    $last_equal_low->{price}
                    - $pivot->{price}
                );

                if ($difference < $tolerance) {

                    push @{$self->{equal_levels}}, {
                        type  => 'EQL',
                        tier  => 'equal',
                        mode  => 'equal',

                        index1 => defined $last_equal_low->{display_index}
                            ? $last_equal_low->{display_index}
                            : $last_equal_low->{index},

                        index2 => defined $pivot->{display_index}
                            ? $pivot->{display_index}
                            : $pivot->{index},

                        confirmed_index1 =>
                            $last_equal_low->{index},

                        confirmed_index2 =>
                            $pivot->{index},

                        price1 => $last_equal_low->{price},
                        price2 => $pivot->{price},

                        price => $pivot->{price},

                        tolerance => $tolerance,
                        difference => $difference,

                        source => 'EqualLowLuxAlgo',
                    };
                }
            }

            $last_equal_low = $pivot;
        }
    }
}


sub _update_liquidity_states {
    my ($self, $bar, $i) = @_;

    return if !$bar;
    return if !defined $i;

    # Número de cierres consecutivos fuera del nivel
    # necesarios para confirmar un Liquidity Run.
    my $run_bars = $self->{confirm_bars} // 3;
    $run_bars = 1 if $run_bars < 1;

    for my $lvl (@{$self->{liquidity} || []}) {

        next if !$lvl;
        next if ref($lvl) ne 'HASH';

        my $type  = $lvl->{type} // '';
        my $price = $lvl->{price};

        next if $type ne 'BSL' && $type ne 'SSL';
        next if !defined $price;

        my $created_index = defined $lvl->{created_index}
            ? $lvl->{created_index}
            : $lvl->{index};

        next if !defined $created_index;

        # El nivel todavía no puede ser barrido en la misma vela
        # donde fue creado.
        next if $i <= $created_index;

        # Un nivel resuelto no vuelve a procesarse.
        next if ($lvl->{state} // '') eq 'Resolved';

        my $high  = $bar->{high};
        my $low   = $bar->{low};
        my $close = $bar->{close};

        next if !defined $high;
        next if !defined $low;
        next if !defined $close;

        # ==========================================================
        # 1. DETECCIÓN DEL PRIMER ROMPIMIENTO DEL NIVEL
        # ==========================================================
        if (($lvl->{state} // '') eq 'Detected') {

            my $level_broken = 0;

            if ($type eq 'BSL') {
                $level_broken = $high > $price ? 1 : 0;
            }
            elsif ($type eq 'SSL') {
                $level_broken = $low < $price ? 1 : 0;
            }

            next if !$level_broken;

            $lvl->{state}         = 'Swept';
            $lvl->{swept_index}   = $i;
            $lvl->{outside_count} = 0;

            # ------------------------------------------------------
            # SWEEP:
            # Rompe con la mecha y regresa en la misma vela.
            # ------------------------------------------------------
            if (
                ($type eq 'BSL' && $close < $price)
                ||
                ($type eq 'SSL' && $close > $price)
            ) {
                $lvl->{classification} = 'Sweep';
                $lvl->{resolved_index} = $i;
                $lvl->{state}          = 'Resolved';

                next;
            }

            # Si la vela que rompe también cierra fuera,
            # cuenta como la primera vela de aceptación.
            if (
                ($type eq 'BSL' && $close > $price)
                ||
                ($type eq 'SSL' && $close < $price)
            ) {
                $lvl->{state}         = 'Acceptance';
                $lvl->{outside_count} = 1;

                # Permite run_bars = 1 si alguna vez se configura así.
                if ($lvl->{outside_count} >= $run_bars) {
                    $lvl->{classification} = 'Run';
                    $lvl->{resolved_index} = $i;
                    $lvl->{state}          = 'Resolved';
                }
            }

            next;
        }

        # ==========================================================
        # 2. NIVEL YA BARRIDO:
        #    CONFIRMAR GRAB O RUN
        # ==========================================================
        next if !defined $lvl->{swept_index};

        my $closed_outside = 0;
        my $closed_inside  = 0;

        if ($type eq 'BSL') {

            # Aceptación alcista por encima de BSL.
            $closed_outside = $close > $price ? 1 : 0;

            # Recuperación bajista bajo BSL.
            $closed_inside = $close < $price ? 1 : 0;
        }
        elsif ($type eq 'SSL') {

            # Aceptación bajista por debajo de SSL.
            $closed_outside = $close < $price ? 1 : 0;

            # Recuperación alcista sobre SSL.
            $closed_inside = $close > $price ? 1 : 0;
        }

        # ----------------------------------------------------------
        # GRAB:
        # Hubo uno o más cierres fuera, pero el precio regresó
        # antes de completar la confirmación del Run.
        # ----------------------------------------------------------
        if ($closed_inside) {

            $lvl->{classification} = 'Grab';
            $lvl->{resolved_index} = $i;
            $lvl->{state}          = 'Resolved';

            next;
        }

        # ----------------------------------------------------------
        # ACCEPTANCE:
        # Sumar cierres consecutivos fuera del nivel.
        # ----------------------------------------------------------
        if ($closed_outside) {

            $lvl->{state} = 'Acceptance';
            $lvl->{outside_count} =
                ($lvl->{outside_count} // 0) + 1;

            # ------------------------------------------------------
            # RUN:
            # Confirmación por cierres consecutivos fuera.
            # ------------------------------------------------------
            if ($lvl->{outside_count} >= $run_bars) {

                $lvl->{classification} = 'Run';
                $lvl->{resolved_index} = $i;
                $lvl->{state}          = 'Resolved';

                next;
            }
        }
        else {
            # Si el cierre coincide exactamente con el nivel,
            # no confirma aceptación ni recuperación.
            #
            # Reiniciamos la secuencia porque los cierres necesarios
            # para Run deben ser consecutivos.
            $lvl->{outside_count} = 0;
            $lvl->{state}         = 'Swept';
        }
    }
}



sub audit_volume_pivots {
    my ($self, $candles, $from, $to) = @_;

    return if !$self->{volume_pivots};

    $from //= 0;
    $to   //= $#$candles;

    print "\n=== AUDITORIA VOLUME PIVOTS $from-$to ===\n";

    for my $p (@{$self->{volume_pivots}}) {
        my $i = $p->{index};
        next if !defined $i;
        next if $i < $from || $i > $to;

        my $bar = $candles->[$i];

        my $time = $bar->{datetime}
            // $bar->{time}
            // $bar->{timestamp}
            // 'SIN_FECHA';

        printf(
            "VOL_PIVOT i=%d time=%s type=%s price=%.2f vol=%.2f avg_vol=%.2f rel_vol=%.2f range_atr=%.2f source=%s\n",
            $i,
            $time,
            $p->{type} // '',
            $p->{price} // 0,
            $p->{volume} // 0,
            $p->{avg_volume} // 0,
            $p->{relative_volume} // 0,
            $p->{range_atr} // 0,
            $p->{source} // ''
        );
    }

    print "===============================\n\n";
}


sub audit_clean_volume_sequence {
    my ($self, $candles, $from, $to) = @_;

    return if !$self->{volume_pivots};

    $from //= 0;
    $to   //= $#$candles;

    print "\n=== AUDITORIA CLEAN VOLUME SEQUENCE $from-$to ===\n";

    my @candidates = grep {
        defined $_->{index}
        && $_->{index} >= $from
        && $_->{index} <= $to
    } @{$self->{volume_pivots}};

    @candidates = sort {
        $a->{index} <=> $b->{index}
            ||
        ($b->{relative_volume} // 0) <=> ($a->{relative_volume} // 0)
    } @candidates;

    my @clean;
    $self->{clean_volume_swings} = \@clean;

    for my $p (@candidates) {
        my $last = $clean[-1];

        # Si es el mismo índice, conserva solo el de mayor range_atr
        if ($last && $last->{index} == $p->{index}) {
            if (($p->{range_atr} // 0) > ($last->{range_atr} // 0)) {
                $clean[-1] = $p;
            }
            next;
        }

        # Regla clave: alternancia HIGH / LOW
        next if $last && ($last->{type} // '') eq ($p->{type} // '');

        push @clean, $p;
    }

    for my $p (@clean) {
        my $i = $p->{index};
        my $bar = $candles->[$i];

        my $time = $bar->{datetime}
            // $bar->{time}
            // $bar->{timestamp}
            // 'SIN_FECHA';

        printf(
            "CLEAN_VOL i=%d time=%s type=%s price=%.2f rel_vol=%.2f range_atr=%.2f\n",
            $i,
            $time,
            $p->{type} // '',
            $p->{price} // 0,
            $p->{relative_volume} // 0,
            $p->{range_atr} // 0
        );
    }

    print "=============================================\n\n";
}
sub audit_liquidity_classification {
    my ($self, $candles) = @_;

    my $run_bars      = $self->{confirm_bars} // 3;

    my %audit = (
        total_resolved          => 0,
        sweep_count             => 0,
        grab_count              => 0,
        run_count               => 0,
        missing_field_errors    => 0,
        sweep_rule_errors       => 0,
        grab_timing_errors      => 0,
        run_confirmation_errors => 0,
        future_leak_errors      => 0,
        duplicate_event_errors  => 0,
        unknown_class_errors    => 0,
        examples                => [],
    );

    my %seen;

    for my $lvl (@{$self->{liquidity} || []}) {

        next if ($lvl->{state} // '') ne 'Resolved';

        $audit{total_resolved}++;

        my $type       = $lvl->{type};
        my $class      = $lvl->{classification};
        my $price      = $lvl->{price};
        my $created_i  = $lvl->{created_index} // $lvl->{index};
        my $swept_i    = $lvl->{swept_index};
        my $resolved_i = $lvl->{resolved_index};

        if (!defined $type || !defined $class || !defined $price ||
            !defined $created_i || !defined $swept_i || !defined $resolved_i) {

            $audit{missing_field_errors}++;
            _audit_push_example(\%audit, "MISSING_FIELD", $lvl);
            next;
        }

        if ($created_i > $swept_i || $swept_i > $resolved_i) {
            $audit{future_leak_errors}++;
            _audit_push_example(\%audit, "FUTURE_LEAK", $lvl);
            next;
        }

       my $key = join('|', $type, sprintf('%.2f', $price), $swept_i, $resolved_i);

        if ($seen{$key}++) {
            $audit{duplicate_event_errors}++;
            _audit_push_example(\%audit, "DUPLICATE", $lvl);
            next;
        }

        my $sweep_bar    = $candles->[$swept_i];
        my $resolved_bar = $candles->[$resolved_i];

        if (!$sweep_bar || !$resolved_bar) {
            $audit{missing_field_errors}++;
            _audit_push_example(\%audit, "MISSING_BAR", $lvl);
            next;
        }

        my $broke_level = 0;

        if ($type eq 'BSL') {
            $broke_level = (($sweep_bar->{high} // 0) > $price) ? 1 : 0;
        }
        elsif ($type eq 'SSL') {
            $broke_level = (($sweep_bar->{low} // 0) < $price) ? 1 : 0;
        }

        if (!$broke_level) {
            $audit{sweep_rule_errors}++;
            _audit_push_example(\%audit, "NO_LEVEL_BREAK", $lvl);
            next;
        }

        if ($class eq 'Sweep') {

            $audit{sweep_count}++;

            my $valid = 0;

            if ($type eq 'BSL') {
                $valid = (($sweep_bar->{high} // 0) > $price &&
                          ($resolved_bar->{close} // 0) < $price);
            }
            elsif ($type eq 'SSL') {
                $valid = (($sweep_bar->{low} // 0) < $price &&
                          ($resolved_bar->{close} // 0) > $price);
            }

            if (!$valid) {
                $audit{sweep_rule_errors}++;
                _audit_push_example(\%audit, "BAD_SWEEP_RULE", $lvl);
            }
        }

        elsif ($class eq 'Grab') {

        $audit{grab_count}++;

        my $bars_after_sweep = $resolved_i - $swept_i;

        # Un Grab no puede resolverse en la misma vela.
        # Si ocurre en la misma vela, corresponde a Sweep.
        if ($bars_after_sweep < 1) {
            $audit{grab_timing_errors}++;
            _audit_push_example(\%audit, "GRAB_ON_SWEEP_BAR", $lvl);
        }

        my $valid_close = 0;

        if ($type eq 'BSL') {
            $valid_close =
                ($resolved_bar->{close} // 0) < $price;
        }
        elsif ($type eq 'SSL') {
            $valid_close =
                ($resolved_bar->{close} // 0) > $price;
        }

        if (!$valid_close) {
            $audit{sweep_rule_errors}++;
            _audit_push_example(\%audit, "BAD_GRAB_CLOSE", $lvl);
        }

        # No puede haber alcanzado la confirmación de Run.
        if (($lvl->{outside_count} // 0) >= $run_bars) {
            $audit{grab_timing_errors}++;
            _audit_push_example(\%audit, "GRAB_AFTER_RUN_CONFIRMATION", $lvl);
        }
    } 

        elsif ($class eq 'Run') {

            $audit{run_count}++;

            my $start = $resolved_i - $run_bars + 1;

            if ($start < $swept_i) {
                $audit{run_confirmation_errors}++;
                _audit_push_example(\%audit, "BAD_RUN_WINDOW", $lvl);
                next;
            }

            my $valid_run = 1;

            for my $j ($start .. $resolved_i) {
                my $bar = $candles->[$j];

                if (!$bar) {
                    $valid_run = 0;
                    last;
                }

                if ($type eq 'BSL') {
                    $valid_run = 0 if (($bar->{close} // 0) <= $price);
                }
                elsif ($type eq 'SSL') {
                    $valid_run = 0 if (($bar->{close} // 0) >= $price);
                }
            }

            if (!$valid_run) {
                $audit{run_confirmation_errors}++;
                _audit_push_example(\%audit, "BAD_RUN_CONFIRMATION", $lvl);
            }
        }

        else {
            $audit{unknown_class_errors}++;
            _audit_push_example(\%audit, "UNKNOWN_CLASS", $lvl);
        }
    }

    $self->{audit}->{liquidity_classification} = \%audit;

    print "\n=== LIQUIDITY CLASSIFICATION AUDIT ===\n";
    printf "Resolved events: %d\n", $audit{total_resolved};
    printf "Sweep: %d | Grab: %d | Run: %d\n",
        $audit{sweep_count}, $audit{grab_count}, $audit{run_count};

    printf "Missing field errors: %d\n",    $audit{missing_field_errors};
    printf "Sweep rule errors: %d\n",       $audit{sweep_rule_errors};
    printf "Grab timing errors: %d\n",      $audit{grab_timing_errors};
    printf "Run confirmation errors: %d\n", $audit{run_confirmation_errors};
    printf "Future leak errors: %d\n",      $audit{future_leak_errors};
    printf "Duplicate event errors: %d\n",  $audit{duplicate_event_errors};
    printf "Unknown class errors: %d\n",    $audit{unknown_class_errors};

    if (@{$audit{examples}}) {
        print "--- Examples ---\n";
        for my $e (@{$audit{examples}}) {
            printf "%s type=%s class=%s price=%.2f created=%s swept=%s resolved=%s\n",
                $e->{error},
                $e->{type} // '',
                $e->{classification} // '',
                $e->{price} // 0,
                defined $e->{created_index} ? $e->{created_index} : '',
                defined $e->{swept_index} ? $e->{swept_index} : '',
                defined $e->{resolved_index} ? $e->{resolved_index} : '';
        }
    }

    print "=======================================\n\n";
}

sub _audit_push_example {
    my ($audit, $error, $lvl) = @_;

    return if @{$audit->{examples}} >= 15;

    push @{$audit->{examples}}, {
        error          => $error,
        type           => $lvl->{type},
        classification => $lvl->{classification},
        price          => $lvl->{price},
        created_index  => $lvl->{created_index} // $lvl->{index},
        swept_index    => $lvl->{swept_index},
        resolved_index => $lvl->{resolved_index},
    };
}


# ==============================================================
# DIY SUPPLY / DEMAND
#
# Usa exclusivamente la estructura externa ya confirmada.
#
# HIGH confirmado -> SUPPLY
# LOW confirmado  -> DEMAND
#
# No crea otro ZigZag y no modifica HH/HL/LH/LL.
# ==============================================================
sub _build_supply_demand_zones {
    my (
        $self,
        $candles,
        $atr_values,
        $until_index,
    ) = @_;

    $candles    ||= [];
    $atr_values ||= [];

    return []
        if !defined $until_index
        || $until_index < 0;

    my @zones;
    my @supply_ids;
    my @demand_ids;

    # ==========================================================
    # PIVOTES PROPIOS DEL DIY
    #
    # Replica:
    # ta.pivothigh(high, 10, 10)
    # ta.pivotlow(low, 10, 10)
    #
    # El pivote se ubica en pivot_index, pero solamente queda
    # confirmado en confirmation_index.
    # ==========================================================
    my $detected_pivots =
        $self->_detect_supply_demand_pivots(
            $candles,
            $until_index,
        );

    my @pivots =
        @{$detected_pivots || []};

    @pivots = sort {
           ($a->{confirmation_index} // -1)
        <=>
           ($b->{confirmation_index} // -1)
        ||
           ($a->{pivot_index} // -1)
        <=>
           ($b->{pivot_index} // -1)
    } @pivots;

    for my $pivot (@pivots) {

        next if !$pivot;
        next if ref($pivot) ne 'HASH';

        my $pivot_index =
            $pivot->{pivot_index}
            // $pivot->{index};

        my $created_index =
            $pivot->{confirmation_index}
            // $pivot_index;

        next if !defined $pivot_index;
        next if !defined $created_index;
        next if $created_index > $until_index;

        my $pivot_bar =
            $candles->[$pivot_index];

        next if !$pivot_bar;

        # El DIY usa ta.atr(50), no el ATR(14) general.
        # Se calcula en la vela donde el pivote queda confirmado.
        my $atr =
            $self->_supply_demand_atr(
                $candles,
                $created_index,
                50,
            );

        next if !defined $atr;
        next if $atr <= 0;

        # Este dato se conserva para auditoría/ML.
        # No bloquea zonas porque require_volume = 0.
        my $validation =
            $self->_validate_supply_demand_origin(
                $candles,
                $atr_values,
                $pivot_index,
            );

        if (
            $self->{supply_demand_require_volume}
            &&
            !$validation->{validated}
        ) {
            next;
        }

        my $type =
            ($pivot->{type} // '') eq 'HIGH'
                ? 'SUPPLY'
                : 'DEMAND';

        my $height =
              $atr
            * (
                (
                    $self->{supply_demand_box_width}
                    // 2.5
                )
                / 10
            );

        next if $height <= 0;

        my ($top, $bottom);

        if ($type eq 'SUPPLY') {
            $top    = $pivot->{price};
            $bottom = $top - $height;
        }
        else {
            $bottom = $pivot->{price};
            $top    = $bottom + $height;
        }

        my $poi =
            ($top + $bottom) / 2;

        next if !$self->_supply_demand_zone_is_separated(
            \@zones,
            $type,
            $poi,
            $atr,
        );

        my $zone = {
            id => join(
                '_',
                'DIY',
                $type,
                $pivot_index,
                $created_index,
            ),

            type   => $type,
            source => 'DIY_SUPPLY_DEMAND',
            tier   => 'diy',

            # Vela donde realmente ocurrió el swing.
            pivot_index => $pivot_index,

            # Momento en que ta.pivot queda confirmado.
            created_index => $created_index,
            confirmed_index => $created_index,

            # La banda comienza visualmente en el swing.
            start_index => $pivot_index,

            # Si sigue activa, se extiende hasta la última vela.
            end_index => $until_index,

            top         => $top,
            bottom      => $bottom,
            poi         => $poi,
            atr         => $atr,
            zone_height => $height,

            state => 'ACTIVE',

            first_touch_index => undef,
            mitigated_index   => undef,
            broken_index      => undef,
            resolved_index    => undef,

            volume =>
                $validation->{volume},

            average_volume =>
                $validation->{average_volume},

            relative_volume =>
                $validation->{relative_volume},

            range_atr =>
                $validation->{range_atr},

            volume_validated =>
                $validation->{validated} ? 1 : 0,
        };

        # No procesar la zona antes de su confirmación.
        $self->_update_supply_demand_zone_state(
            $zone,
            $candles,
            $created_index + 1,
            $until_index,
        );

        push @zones, $zone;

        # El DIY conserva como máximo 20 zonas de cada tipo.
        if ($type eq 'SUPPLY') {
            push @supply_ids, $zone->{id};

            if (
                @supply_ids
                >
                (
                    $self->{supply_demand_history}
                    // 20
                )
            ) {
                my $remove_id =
                    shift @supply_ids;

                @zones = grep {
                    ($_->{id} // '')
                    ne
                    $remove_id
                } @zones;
            }
        }
        else {
            push @demand_ids, $zone->{id};

            if (
                @demand_ids
                >
                (
                    $self->{supply_demand_history}
                    // 20
                )
            ) {
                my $remove_id =
                    shift @demand_ids;

                @zones = grep {
                    ($_->{id} // '')
                    ne
                    $remove_id
                } @zones;
            }
        }
    }

    # ==========================================================
    # El DIY mantiene:
    # - hasta 20 zonas activas/mitigadas por tipo;
    # - solamente 5 líneas históricas rotas por tipo.
    # ==========================================================
    my @active_or_mitigated =
        grep {
            ($_->{state} // 'ACTIVE')
            ne 'BROKEN'
        } @zones;

    my @broken_supply =
        grep {
               ($_->{state} // '')
               eq 'BROKEN'
            && ($_->{type} // '')
               eq 'SUPPLY'
        } @zones;

    my @broken_demand =
        grep {
               ($_->{state} // '')
               eq 'BROKEN'
            && ($_->{type} // '')
               eq 'DEMAND'
        } @zones;

    @broken_supply = sort {
        ($a->{broken_index} // 0)
        <=>
        ($b->{broken_index} // 0)
    } @broken_supply;

    @broken_demand = sort {
        ($a->{broken_index} // 0)
        <=>
        ($b->{broken_index} // 0)
    } @broken_demand;

    if (@broken_supply > 5) {
        @broken_supply =
            @broken_supply[
                $#broken_supply - 4
                ..
                $#broken_supply
            ];
    }

    if (@broken_demand > 5) {
        @broken_demand =
            @broken_demand[
                $#broken_demand - 4
                ..
                $#broken_demand
            ];
    }

    @zones = (
        @active_or_mitigated,
        @broken_supply,
        @broken_demand,
    );

    @zones = sort {
           ($a->{start_index} // 0)
        <=>
           ($b->{start_index} // 0)
        ||
           ($a->{created_index} // 0)
        <=>
           ($b->{created_index} // 0)
    } @zones;

    return \@zones;
}


sub _validate_supply_demand_origin {
    my (
        $self,
        $candles,
        $atr_values,
        $index,
    ) = @_;

    my $bar = $candles->[$index];

    return {
        validated       => 0,
        volume          => 0,
        average_volume  => 0,
        relative_volume => 0,
        range_atr       => 0,
    } if !$bar;

    my $lookback =
        $self->{supply_demand_volume_lookback}
        // 20;

    my $start =
        $index - $lookback;

    $start = 0
        if $start < 0;

    my $volume_sum   = 0;
    my $volume_count = 0;

    # El promedio utiliza únicamente velas anteriores.
    # No incluye la vela del pivote.
    for my $i ($start .. $index - 1) {
        my $previous = $candles->[$i];
        next if !$previous;

        $volume_sum +=
            $previous->{volume} // 0;

        $volume_count++;
    }

    my $average_volume =
        $volume_count > 0
            ? $volume_sum / $volume_count
            : 0;

    my $volume =
        $bar->{volume} // 0;

    my $relative_volume =
        $average_volume > 0
            ? $volume / $average_volume
            : 0;

    my $atr =
        $atr_values->[$index] // 0;

    my $range =
          ($bar->{high} // 0)
        - ($bar->{low}  // 0);

    my $range_atr =
        $atr > 0
            ? $range / $atr
            : 0;

    my $validated =
           $average_volume > 0
        && $relative_volume
            >=
            (
                $self->{supply_demand_volume_mult}
                // 1.5
            )
        && $range_atr
            >=
            (
                $self->{supply_demand_range_atr_min}
                // 0.80
            );

    return {
        validated       => $validated ? 1 : 0,
        volume          => $volume,
        average_volume  => $average_volume,
        relative_volume => $relative_volume,
        range_atr       => $range_atr,
    };
}


sub _supply_demand_zone_is_separated {
    my (
        $self,
        $zones,
        $type,
        $new_poi,
        $atr,
    ) = @_;

    return 1
        if !$zones
        || ref($zones) ne 'ARRAY';

    # Igual que el DIY:
    # atr_threshold = atrpoi * 2
    my $threshold =
        $atr * 2.0;

    for my $zone (@$zones) {
        next if !$zone;
        next if ref($zone) ne 'HASH';
        next if !defined $zone->{poi};

        # El DIY mantiene arreglos distintos:
        # current_supply_box y current_demand_box.
        # Por eso Supply solo se compara con Supply
        # y Demand únicamente con Demand.
        next
            if ($zone->{type} // '')
            ne
            ($type // '');

        # Las zonas rotas ya fueron eliminadas del arreglo
        # activo en el DIY, por lo que no bloquean otras.
        next
            if ($zone->{state} // 'ACTIVE')
            eq 'BROKEN';

        my $upper_boundary =
            $zone->{poi} + $threshold;

        my $lower_boundary =
            $zone->{poi} - $threshold;

        return 0
            if $new_poi >= $lower_boundary
            && $new_poi <= $upper_boundary;
    }

    return 1;
}

sub _update_supply_demand_zone_state {
    my (
        $self,
        $zone,
        $candles,
        $from_index,
        $until_index,
    ) = @_;

    return if !$zone;
    return if !$candles;
    return if ref($candles) ne 'ARRAY';
    return if $from_index > $until_index;

    my $created_index =
        $zone->{created_index}
        // 0;

    for my $i ($from_index .. $until_index) {
        my $bar = $candles->[$i];

        next if !$bar;
        next if ref($bar) ne 'HASH';

        my $high  = $bar->{high};
        my $low   = $bar->{low};
        my $close = $bar->{close};

        next if !defined $high;
        next if !defined $low;
        next if !defined $close;

        # Las primeras velas posteriores al pivote todavía
        # forman parte de la creación de la zona.
        my $can_mitigate =
            $i > $created_index + 1;

        my $touches_zone =
               $can_mitigate
            && $high >= $zone->{bottom}
            && $low  <= $zone->{top};

        # Una mitigación solamente cambia su estado informativo.
        # La zona sigue extendiéndose.
        if (
            $touches_zone
            &&
            !defined $zone->{first_touch_index}
        ) {
            $zone->{first_touch_index} = $i;
            $zone->{mitigated_index}   = $i;
            $zone->{state}             = 'MITIGATED';
        }

        # Igual que el DIY: la zona únicamente finaliza
        # cuando el cierre atraviesa su borde exterior.
        my $broken =
            $zone->{type} eq 'SUPPLY'
                ? ($close >= $zone->{top})
                : ($close <= $zone->{bottom});

        if ($broken) {
            $zone->{state}          = 'BROKEN';
            $zone->{broken_index}   = $i;
            $zone->{resolved_index} = $i;
            $zone->{end_index}      = $i;

            last;
        }
    }
}


sub _detect_supply_demand_pivots {
    my (
        $self,
        $candles,
        $until_index,
    ) = @_;

    $candles ||= [];

    my $length =
        $self->{supply_demand_swing_length}
        // 10;

    $length = 1
        if $length < 1;

    
        return []
        if !defined $until_index
        || $until_index < ($length * 2);

        my @pivots;
    # Para confirmar un pivote en i necesitamos:
    # length velas anteriores y length velas posteriores.
    #
    # Pero se registra como creado únicamente cuando
    # esas velas posteriores ya existen:
    #
    # confirmation_index = pivot_index + length
    for my $pivot_index (
        $length
        ..
        $until_index - $length
    ) {
        my $pivot_bar =
            $candles->[$pivot_index];

        next if !$pivot_bar;

        my $pivot_high =
            $pivot_bar->{high};

        my $pivot_low =
            $pivot_bar->{low};

        next if !defined $pivot_high;
        next if !defined $pivot_low;

        my $is_high = 1;
        my $is_low  = 1;

        for my $j (
            $pivot_index - $length
            ..
            $pivot_index + $length
        ) {
            next if $j == $pivot_index;

            my $bar = $candles->[$j];

            if (!$bar) {
                $is_high = 0;
                $is_low  = 0;
                last;
            }

            if (
                !defined $bar->{high}
                || $bar->{high} >= $pivot_high
            ) {
                $is_high = 0;
            }

            if (
                !defined $bar->{low}
                || $bar->{low} <= $pivot_low
            ) {
                $is_low = 0;
            }

            last
                if !$is_high
                && !$is_low;
        }

        my $confirmation_index =
            $pivot_index + $length;

        if ($is_high) {
            push @pivots, {
                type               => 'HIGH',
                price              => $pivot_high,
                index              => $pivot_index,
                pivot_index        => $pivot_index,
                confirmation_index => $confirmation_index,
            };
        }
        elsif ($is_low) {
            push @pivots, {
                type               => 'LOW',
                price              => $pivot_low,
                index              => $pivot_index,
                pivot_index        => $pivot_index,
                confirmation_index => $confirmation_index,
            };
        }
    }

    return \@pivots;
}

sub _supply_demand_atr {
    my (
        $self,
        $candles,
        $index,
        $period,
    ) = @_;

    $period //= 50;

    return 0
        if !$candles
        || ref($candles) ne 'ARRAY'
        || !defined $index
        || $index < 0
        || $period < 1;

    my @true_ranges;

    for my $i (0 .. $index) {
        my $bar =
            $candles->[$i];

        next if !$bar;
        next if !defined $bar->{high};
        next if !defined $bar->{low};

        my $tr =
            $bar->{high}
            -
            $bar->{low};

        if ($i > 0) {
            my $previous =
                $candles->[$i - 1];

            if (
                $previous
                && defined $previous->{close}
            ) {
                my $high_gap =
                    abs(
                        $bar->{high}
                        -
                        $previous->{close}
                    );

                my $low_gap =
                    abs(
                        $bar->{low}
                        -
                        $previous->{close}
                    );

                $tr = $high_gap
                    if $high_gap > $tr;

                $tr = $low_gap
                    if $low_gap > $tr;
            }
        }

        push @true_ranges, $tr;
    }

    return 0
        if !@true_ranges;

    # Semilla de la RMA: promedio de los primeros period TR.
    my $seed_count =
        @true_ranges < $period
            ? scalar(@true_ranges)
            : $period;

    my $seed_sum = 0;

    for my $i (0 .. $seed_count - 1) {
        $seed_sum +=
            $true_ranges[$i];
    }

    my $atr =
        $seed_sum / $seed_count;

    # Wilder RMA:
    # ATR = ((ATR_anterior * (period - 1)) + TR) / period
    for my $i ($seed_count .. $#true_ranges) {
        $atr =
            (
                $atr * ($period - 1)
                +
                $true_ranges[$i]
            ) / $period;
        }

    return $atr;
}

1;