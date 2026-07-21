package Market::Indicators::SMC_Structures;

use strict;
use warnings;

sub new {
    my ($class, %args) = @_;

    my $self = {
        pivots         => [],
        structure      => [],
        events         => [],

        fvg            => [],
        order_blocks   => [],
        choch_atr_mult => $args{choch_atr_mult} // 2.0,

                prefix         => $args{prefix} // '',
        mode           => $args{mode}   // 'external',

        # Equivalente al Internal Confluence Filter del indicador base.
        # Solo afecta la estructura interna.
        internal_confluence => $args{internal_confluence} // 0,

        audit => {
            pivots => [],
            labels => [],
            bos    => [],
            choch  => [],
        },
        
    };

    return bless $self, $class;
}

sub _find_break_index {
    my ($self, $market, $from_i, $to_i, $price, $direction) = @_;

    return $to_i if !$market;
    return $to_i if !defined $from_i || !defined $to_i || !defined $price;

    my $data = $market->get_slice($from_i, $to_i);

    for my $local_i (0 .. $#$data) {
        my $global_i = $from_i + $local_i;
        next if $global_i <= $from_i;

        my $close = $data->[$local_i]{close};

        if ($direction eq 'UP' && $close > $price) {
            return $global_i;
        }

        if ($direction eq 'DOWN' && $close < $price) {
            return $global_i;
        }
    }

    return $to_i;
}

sub _audit_events_health {
    my ($self) = @_;

    my $errors = {
        bos_direction_errors     => 0,
        choch_direction_errors   => 0,
        break_price_errors       => 0,
        duplicate_event_errors   => 0,
        long_event_warnings      => 0,
    };

    my %seen;

    for my $e (@{$self->{events}}) {

        my $type = $e->{raw_type} // '';
        next if !$type;

        my $key = join('|',
            $type,
            $e->{index} // 'undef',
            $e->{pivot_index} // 'undef'
        );

        if ($seen{$key}++) {
            $errors->{duplicate_event_errors}++;

            print "DUPLICATE EVENT ERROR type=$type index=$e->{index} pivot=$e->{pivot_index}\n";
        }

        my $pivot_price = $e->{pivot_price};
        my $break_price = $e->{break_price};

        next if !defined $pivot_price || !defined $break_price;

        if ($type =~ /UP/) {
            if ($break_price <= $pivot_price) {
                $errors->{break_price_errors}++;

                print "BREAK PRICE ERROR UP type=$type pivot_price=$pivot_price break_price=$break_price index=$e->{index}\n";
            }
        }

        if ($type =~ /DOWN/) {
            if ($break_price >= $pivot_price) {
                $errors->{break_price_errors}++;

                print "BREAK PRICE ERROR DOWN type=$type pivot_price=$pivot_price break_price=$break_price index=$e->{index}\n";
            }
        }

        if ($type =~ /BOS/ && $type !~ /UP|DOWN/) {
            $errors->{bos_direction_errors}++;
            print "BOS DIRECTION ERROR type=$type index=$e->{index}\n";
        }

        if ($type =~ /CHoCH/ && $type !~ /UP|DOWN/) {
            $errors->{choch_direction_errors}++;
            print "CHoCH DIRECTION ERROR type=$type index=$e->{index}\n";
        }

        my $dist = abs(($e->{break_index} // $e->{index}) - ($e->{pivot_index} // $e->{index}));

        if ($dist > 1500) {
            $errors->{long_event_warnings}++;

            print "LONG EVENT WARNING type=$type pivot=$e->{pivot_index} break=$e->{break_index} dist=$dist price=$pivot_price\n";
        }
    }

    return $errors;
}

sub _is_real_cross_up {
    my ($self, $previous_close, $current_close, $level) = @_;

    return 0 if !defined $previous_close;
    return 0 if !defined $current_close;
    return 0 if !defined $level;

    # Equivalente práctico a:
    # ta.crossover(close, level)
    return (
        $previous_close <= $level
        && $current_close > $level
    ) ? 1 : 0;
}

sub _is_real_cross_down {
    my ($self, $previous_close, $current_close, $level) = @_;

    return 0 if !defined $previous_close;
    return 0 if !defined $current_close;
    return 0 if !defined $level;

    # Equivalente práctico a:
    # ta.crossunder(close, level)
    return (
        $previous_close >= $level
        && $current_close < $level
    ) ? 1 : 0;
}

sub _passes_internal_confluence {
    my ($self, $bar, $direction) = @_;

    return 1 if $self->{mode} ne 'internal';
    return 1 if !$self->{internal_confluence};
    return 0 if !$bar;

    my $open  = $bar->{open};
    my $high  = $bar->{high};
    my $low   = $bar->{low};
    my $close = $bar->{close};

    return 0 if !defined $open;
    return 0 if !defined $high;
    return 0 if !defined $low;
    return 0 if !defined $close;

    my $upper_wick = $high - ($close > $open ? $close : $open);
    my $lower_wick = ($close < $open ? $close : $open) - $low;

    if ($direction eq 'UP') {
        return $upper_wick > $lower_wick ? 1 : 0;
    }

    if ($direction eq 'DOWN') {
        return $upper_wick < $lower_wick ? 1 : 0;
    }

    return 1;
}

sub _same_price {
    my ($self, $a, $b) = @_;

    return 0 if !defined $a || !defined $b;

    # Los precios del CSV normalmente tienen precisión limitada.
    # La tolerancia evita errores binarios de punto flotante.
    return abs($a - $b) < 0.0000001 ? 1 : 0;
}

sub _register_structure_event {
    my ($self, %args) = @_;

    my $direction    = $args{direction};
    my $trend_before = $args{trend_before};
    my $pivot        = $args{pivot};
    my $bar          = $args{bar};
    my $index        = $args{index};

    return if !$pivot;
    return if !$bar;
    return if !defined $index;

    my $event;

    if ($direction eq 'UP') {
        $event = $trend_before eq 'DOWN'
            ? 'CHoCH_UP'
            : 'BOS_UP';
    }
    elsif ($direction eq 'DOWN') {
        $event = $trend_before eq 'UP'
            ? 'CHoCH_DOWN'
            : 'BOS_DOWN';
    }
    else {
        return;
    }

    my $break_price = $bar->{close};
    my $pivot_price = $pivot->{price};

    my $event_record = {
        type     => $self->{prefix} . $event,
        raw_type => $event,
        mode     => $self->{mode},

        index       => $index,
        break_index => $index,
        break_price => $break_price,

        # El nivel se activa en $pivot->{index}, pero se representa
        # visualmente desde el extremo real.
        pivot_index => defined $pivot->{display_index}
            ? $pivot->{display_index}
            : $pivot->{index},

        pivot_confirmed_index => $pivot->{index},
        pivot_price => $pivot_price,

        price => $pivot_price,
        pivot => $pivot->{label},

        trend_before => $trend_before,
        trend_after  => $direction eq 'UP' ? 'UP' : 'DOWN',

        break_size => $direction eq 'UP'
            ? $break_price - $pivot_price
            : $pivot_price - $break_price,
    };

    push @{$self->{events}}, $event_record;

    if ($event =~ /CHoCH/) {
        push @{$self->{audit}->{choch}}, $event_record;
    }
    else {
        push @{$self->{audit}->{bos}}, $event_record;
    }

    return $event_record;
}

sub calculate {
    my ($self, $pivots, $market, %args) = @_;

    $pivots ||= [];

    $self->{pivots}       = $pivots;
    $self->{structure}    = [];
    $self->{events}       = [];
    $self->{fvg}          = [];
    $self->{order_blocks} = [];

    $self->{audit} = {
        labels => [],
        bos    => [],
        choch  => [],
    };

    # Estos niveles externos son opcionales.
    # Se usarán en el motor interno para evitar que una estructura
    # interna duplique exactamente el nivel de la estructura externa.
    my $external_highs = $args{external_highs} || {};
    my $external_lows  = $args{external_lows}  || {};

    my $last_high;
    my $last_low;

    # Pivotes organizados por índice para procesar todo vela por vela.
    my %pivots_by_index;

    for my $pivot (@$pivots) {
        next if !$pivot;
        next if !defined $pivot->{index};
        next if !defined $pivot->{price};
        next if !defined $pivot->{type};
        next if $pivot->{type} ne 'HIGH' && $pivot->{type} ne 'LOW';

        my $label;

        if ($pivot->{type} eq 'HIGH') {
            $label = !defined $last_high
                ? 'H'
                : (
                    $pivot->{price} > $last_high->{price}
                        ? 'HH'
                        : 'LH'
                );

            $last_high = $pivot;
        }
        else {
            $label = !defined $last_low
                ? 'L'
                : (
                    $pivot->{price} > $last_low->{price}
                        ? 'HL'
                        : 'LL'
                );

            $last_low = $pivot;
        }

        my $prepared_pivot = {
            %$pivot,
            label     => $label,
            raw_label => $label,
            mode      => $self->{mode},
            crossed   => 0,
        };

        push @{$pivots_by_index{$pivot->{index}}}, $prepared_pivot;

        push @{$self->{structure}}, {
            %$pivot,
            label     => $self->{prefix} . $label,
            raw_label => $label,
            mode      => $self->{mode},
            event     => undef,
        };

        push @{$self->{audit}->{labels}}, {
            index  => $pivot->{index},
            type   => $pivot->{type},
            price  => $pivot->{price},
            label  => $label,
            mode   => $self->{mode},
            source => $pivot->{source} // 'UNKNOWN',
            event  => undef,
            trend  => undef,
        };
    }

    # Si no existe mercado, se devuelven por lo menos las etiquetas.
    if (!$market || $market->last_index() < 0) {
        return {
            structure    => $self->{structure},
            events       => $self->{events},
            fvg          => [],
            order_blocks => [],
            state        => 'UNKNOWN',
            audit        => $self->{audit},
        };
    }

    my $trend = 'UNKNOWN';

    my $active_high;
    my $active_low;

    my $last_market_index = defined $args{until_index}
    ? $args{until_index}
    : $market->last_index();

    my $market_last_index = $market->last_index();

    $last_market_index = $market_last_index
        if $last_market_index > $market_last_index;

    $last_market_index = 0
        if $last_market_index < 0;

    # El cálculo del indicador se ejecuta hasta la última vela
    # actualmente disponible. En Replay, MarketData y ChartEngine
    # ya limitan este valor mediante update_smc_overlay().
    my $previous_close;

    for my $i (0 .. $last_market_index) {

        my $bar = $market->get_candle($i);
        next if !$bar;

        # ---------------------------------------------------------
        # 1. Activar los pivotes correspondientes a esta vela
        # ---------------------------------------------------------
        if ($pivots_by_index{$i}) {

            for my $pivot (@{$pivots_by_index{$i}}) {

                if ($pivot->{type} eq 'HIGH') {
                    $active_high = {
                        %$pivot,
                        crossed => 0,
                    };
                }
                elsif ($pivot->{type} eq 'LOW') {
                    $active_low = {
                        %$pivot,
                        crossed => 0,
                    };
                }
            }
        }

        my $close = $bar->{close};

        if (!defined $close) {
            next;
        }

        # No se puede comprobar crossover/crossunder sin cierre anterior.
        if (!defined $previous_close) {
            $previous_close = $close;
            next;
        }

        # ---------------------------------------------------------
        # 2. Comprobar ruptura alcista del HIGH activo
        # ---------------------------------------------------------
        if (
            defined $active_high
            && !$active_high->{crossed}
            && $self->_is_real_cross_up(
                $previous_close,
                $close,
                $active_high->{price}
            )
        ) {
            my $allow_event = 1;

            # En el indicador de referencia:
            # internalHigh.currentLevel != swingHigh.currentLevel
            if ($self->{mode} eq 'internal') {
                for my $external_price (keys %$external_highs) {
                    if ($self->_same_price(
                        $active_high->{price},
                        $external_price
                    )) {
                        $allow_event = 0;
                        last;
                    }
                }
            }

            if (
                $allow_event
                && $self->_passes_internal_confluence($bar, 'UP')
            ) {
                my $event_record = $self->_register_structure_event(
                    direction    => 'UP',
                    trend_before => $trend,
                    pivot        => $active_high,
                    bar          => $bar,
                    index        => $i,
                );

                if ($event_record) {
                    $active_high->{crossed} = 1;
                    $trend = 'UP';
                }
            }
        }

        # ---------------------------------------------------------
        # 3. Comprobar ruptura bajista del LOW activo
        # ---------------------------------------------------------
        if (
            defined $active_low
            && !$active_low->{crossed}
            && $self->_is_real_cross_down(
                $previous_close,
                $close,
                $active_low->{price}
            )
        ) {
            my $allow_event = 1;

            # En el indicador de referencia:
            # internalLow.currentLevel != swingLow.currentLevel
            if ($self->{mode} eq 'internal') {
                for my $external_price (keys %$external_lows) {
                    if ($self->_same_price(
                        $active_low->{price},
                        $external_price
                    )) {
                        $allow_event = 0;
                        last;
                    }
                }
            }

            if (
                $allow_event
                && $self->_passes_internal_confluence($bar, 'DOWN')
            ) {
                my $event_record = $self->_register_structure_event(
                    direction    => 'DOWN',
                    trend_before => $trend,
                    pivot        => $active_low,
                    bar          => $bar,
                    index        => $i,
                );

                if ($event_record) {
                    $active_low->{crossed} = 1;
                    $trend = 'DOWN';
                }
            }
        }

        $previous_close = $close;
    }

    # Asociar cada evento con el punto estructural que realmente rompió.
    my %events_by_pivot;

    for my $event (@{$self->{events}}) {

    my $association_index =
        defined $event->{pivot_confirmed_index}
            ? $event->{pivot_confirmed_index}
            : $event->{pivot_index};

    next if !defined $association_index;

    push @{$events_by_pivot{$association_index}},
        $event->{raw_type};
    }

    for my $point (@{$self->{structure}}) {
        my $event_names = $events_by_pivot{$point->{index}};

        $point->{event} = $event_names && @$event_names
            ? join(',', @$event_names)
            : undef;
    }

    for my $audit_label (@{$self->{audit}->{labels}}) {
        my $event_names = $events_by_pivot{$audit_label->{index}};

        $audit_label->{event} = $event_names && @$event_names
            ? join(',', @$event_names)
            : undef;

        $audit_label->{trend} = $trend;
    }

    # Ahora se calculan hasta la última vela disponible,
    # no solamente hasta el último pivote.
    $self->{fvg} = $self->_detect_fvg(
        $market,
        $last_market_index
    );
    $self->{order_blocks} =
        $self->_detect_order_blocks(
            $market,
            until_index       => $last_market_index,
            mitigation_source => 'HIGHLOW',
        );

    $self->{audit}->{event_health} =
        $self->_audit_events_health();

    if ($self->{debug_audit}) {
        print "\n---- SMC EVENT HEALTH ------------\n";
        print "BOS direction errors     : "
            . $self->{audit}->{event_health}->{bos_direction_errors}
            . "\n";

        print "CHoCH direction errors   : "
            . $self->{audit}->{event_health}->{choch_direction_errors}
            . "\n";

        print "Break price errors       : "
            . $self->{audit}->{event_health}->{break_price_errors}
            . "\n";

        print "Duplicate event errors   : "
            . $self->{audit}->{event_health}->{duplicate_event_errors}
            . "\n";

        print "Long event warnings      : "
            . $self->{audit}->{event_health}->{long_event_warnings}
            . "\n";

        print "----------------------------------\n";
    }

    return {
        structure    => $self->{structure},
        events       => $self->{events},
        fvg          => $self->{fvg},
        order_blocks => $self->{order_blocks},
        state        => $trend,
        audit        => $self->{audit},
    };
}

sub _zone_mitigation_percent {
    my (
        $self,
        $original_top,
        $original_bottom,
        $current_top,
        $current_bottom,
        $direction
    ) = @_;

    return 0 if !defined $original_top;
    return 0 if !defined $original_bottom;
    return 0 if !defined $current_top;
    return 0 if !defined $current_bottom;

    my $original_size =
        abs($original_top - $original_bottom);

    return 100 if $original_size <= 0;

    my $remaining_size =
        abs($current_top - $current_bottom);

    my $mitigated =
        1 - ($remaining_size / $original_size);

    $mitigated = 0 if $mitigated < 0;
    $mitigated = 1 if $mitigated > 1;

    return $mitigated * 100;
}

sub _detect_fvg {
    my ($self, $market, $last_index) = @_;

    my @fvg;

    return \@fvg if !$market;
    return \@fvg if !defined $last_index;
    return \@fvg if $last_index < 3;

    my $market_last_index = $market->last_index();

    $last_index = $market_last_index
        if $last_index > $market_last_index;

    return \@fvg if $last_index < 3;

    my $candles = $market->get_slice(0, $last_index);

    return \@fvg if !$candles;
    return \@fvg if ref($candles) ne 'ARRAY';
    return \@fvg if @$candles < 4;

    for my $i (3 .. $#$candles) {

        # Equivalencia con el Pine:
        #
        # isBullishFVG = high[3] < low[1]
        # isBearishFVG = low[3]  > high[1]
        my $left_bar  = $candles->[$i - 3];
        my $right_bar = $candles->[$i - 1];

        next if !$left_bar;
        next if !$right_bar;

        # ==========================================================
        # FVG ALCISTA
        #
        # top    = low[1]
        # bottom = high[3]
        # ==========================================================
        if (
            defined $left_bar->{high}
            && defined $right_bar->{low}
            && $left_bar->{high} < $right_bar->{low}
        ) {
            my $top    = $right_bar->{low};
            my $bottom = $left_bar->{high};

            my $left_index = $i - 2;

            my $mitigated       = 0;
            my $mitigated_index = undef;

            # El FVG queda confirmado en i.
            # Solo se comprueban velas posteriores a su creación.
            for my $j ($i .. $#$candles) {

                my $bar = $candles->[$j];

                next if !$bar;
                next if !defined $bar->{low};

                # Regla del proyecto:
                # el primer toque al borde superior mitiga el FVG.
                if ($bar->{low} <= $top) {
                    $mitigated       = 1;
                    $mitigated_index = $j;
                    last;
                }
            }

            push @fvg, {
                type => 'BULLISH_FVG',
                mode => $self->{mode},

                index       => $i,
                left_index  => $left_index,

                # Si fue mitigado, se registra hasta esa vela.
                # Si sigue activo, llega hasta el límite actual
                # del mercado o del Replay.
                right_index => defined $mitigated_index
                    ? $mitigated_index
                    : $last_index,

                top    => $top,
                bottom => $bottom,

                original_top    => $top,
                original_bottom => $bottom,

                mitigated => $mitigated,

                # En este proyecto, mitigated representa el primer contacto.
                # No significa necesariamente que el FVG haya sido rellenado
                # por completo.
                fully_mitigated => 0,

                mitigated_index => $mitigated_index,

                active => $mitigated ? 0 : 1,

                source => 'LUDOGH68_FVG_FIRST_TOUCH',
            };
        }

        # ==========================================================
        # FVG BAJISTA
        #
        # top    = low[3]
        # bottom = high[1]
        # ==========================================================
        if (
            defined $left_bar->{low}
            && defined $right_bar->{high}
            && $left_bar->{low} > $right_bar->{high}
        ) {
            my $top    = $left_bar->{low};
            my $bottom = $right_bar->{high};

            my $left_index = $i - 2;

            my $mitigated       = 0;
            my $mitigated_index = undef;

            for my $j ($i .. $#$candles) {

                my $bar = $candles->[$j];

                next if !$bar;
                next if !defined $bar->{high};

                # Regla del proyecto:
                # el primer toque al borde inferior mitiga el FVG.
                if ($bar->{high} >= $bottom) {
                    $mitigated       = 1;
                    $mitigated_index = $j;
                    last;
                }
            }

            push @fvg, {
                type => 'BEARISH_FVG',
                mode => $self->{mode},

                index       => $i,
                left_index  => $left_index,

                right_index => defined $mitigated_index
                    ? $mitigated_index
                    : $last_index,

                top    => $top,
                bottom => $bottom,

                original_top    => $top,
                original_bottom => $bottom,

                mitigated => $mitigated,

                # El primer contacto no implica relleno completo del FVG.
                fully_mitigated => 0,

                mitigated_index => $mitigated_index,

                active => $mitigated ? 0 : 1,

                source => 'LUDOGH68_FVG_FIRST_TOUCH',
            };
        }
    }

    return \@fvg;
}



sub _detect_order_blocks {
    my ($self, $market, %args) = @_;

    my @order_blocks;

    return \@order_blocks if !$market;

    my $last_index = defined $args{until_index}
        ? $args{until_index}
        : $market->last_index();

    my $market_last = $market->last_index();

    $last_index = $market_last
        if $last_index > $market_last;

    # LuxAlgo permite:
    #
    # HIGHLOW → mechas
    # CLOSE   → cierre
    #
    # Empezamos con HIGHLOW para aproximarnos al valor por defecto.
    my $mitigation_source =
        $args{mitigation_source} // 'HIGHLOW';

    for my $event (@{$self->{events} || []}) {

        next if !$event;
        next if ref($event) ne 'HASH';

        my $raw_type = $event->{raw_type} // '';

        next if $raw_type !~ /UP|DOWN/;

        # El tramo debe comenzar en la ubicación real del pivote.
        # pivot_confirmed_index indica cuándo se confirmó, pero puede
        # dejar fuera la vela que originó el Order Block.
        my $from_index = defined $event->{pivot_index}
            ? $event->{pivot_index}
            : $event->{pivot_confirmed_index};

        my $break_index = defined $event->{break_index}
            ? $event->{break_index}
            : $event->{index};

        next if !defined $from_index;
        next if !defined $break_index;
        next if $break_index <= $from_index;
        # En Replay o cálculos parciales no deben procesarse
        # rupturas que todavía no han ocurrido.
        next if $break_index > $last_index;

        my $candles =
            $market->get_slice($from_index, $break_index);

        next if !$candles;
        next if ref($candles) ne 'ARRAY';
        next if !@$candles;

        my $selected_local_index;

    # ==========================================================
    # SELECCIÓN DEL ORIGEN DEL ORDER BLOCK
    #
    # Bullish OB:
    #   última vela bajista anterior al rompimiento alcista.
    #
    # Bearish OB:
    #   última vela alcista anterior al rompimiento bajista.
    #
    # El recorrido se realiza hacia atrás para seleccionar la vela
    # opuesta más cercana al impulso que produjo el BOS o CHoCH.
    # ==========================================================

    if ($raw_type =~ /UP/) {

        # ------------------------------------------------------
        # BULLISH ORDER BLOCK
        # Buscar la última vela bajista antes de la ruptura.
        # ------------------------------------------------------
        for (
            my $j = $#$candles - 1;
            $j >= 0;
            $j--
        ) {
            my $bar = $candles->[$j];

            next if !$bar;
            next if !defined $bar->{open};
            next if !defined $bar->{close};
            next if !defined $bar->{high};
            next if !defined $bar->{low};

            if ($bar->{close} < $bar->{open}) {
                $selected_local_index = $j;
                last;
            }
        }

        # Respaldo:
        # si no existe una vela bajista, utilizar el mínimo
        # del tramo, sin incluir la vela de ruptura.
        if (!defined $selected_local_index) {

            my $best_low;

            for my $j (0 .. $#$candles - 1) {
                my $bar = $candles->[$j];

                next if !$bar;
                next if !defined $bar->{low};
                next if !defined $bar->{high};

                if (
                    !defined $best_low
                    || $bar->{low} < $best_low
                ) {
                    $best_low = $bar->{low};
                    $selected_local_index = $j;
                }
            }
        }
    }
    elsif ($raw_type =~ /DOWN/) {

        # ------------------------------------------------------
        # BEARISH ORDER BLOCK
        # Buscar la última vela alcista antes de la ruptura.
        # ------------------------------------------------------
        for (
            my $j = $#$candles - 1;
            $j >= 0;
            $j--
        ) {
            my $bar = $candles->[$j];

            next if !$bar;
            next if !defined $bar->{open};
            next if !defined $bar->{close};
            next if !defined $bar->{high};
            next if !defined $bar->{low};

            if ($bar->{close} > $bar->{open}) {
                $selected_local_index = $j;
                last;
            }
        }

        # Respaldo:
        # si no existe una vela alcista, utilizar el máximo
        # del tramo, sin incluir la vela de ruptura.
        if (!defined $selected_local_index) {

            my $best_high;

            for my $j (0 .. $#$candles - 1) {
                my $bar = $candles->[$j];

                next if !$bar;
                next if !defined $bar->{low};
                next if !defined $bar->{high};

                if (
                    !defined $best_high
                    || $bar->{high} > $best_high
                ) {
                    $best_high = $bar->{high};
                    $selected_local_index = $j;
                }
            }
        }
    }

        next if !defined $selected_local_index;

        my $ob_bar = $candles->[$selected_local_index];

        next if !$ob_bar;
        next if !defined $ob_bar->{high};
        next if !defined $ob_bar->{low};

        my $ob_index =
            $from_index + $selected_local_index;

        my $type = $raw_type =~ /UP/
            ? 'BULLISH_OB'
            : 'BEARISH_OB';

        my $touched = 0;
        my $first_touch_index;
        my $invalidated = 0;
        my $invalidated_index;

        # Revisar exclusivamente velas posteriores a la ruptura.
        for my $i ($break_index + 1 .. $last_index) {

            my $bar = $market->get_candle($i);
            next if !$bar;

            my $high  = $bar->{high};
            my $low   = $bar->{low};
            my $close = $bar->{close};

            # ------------------------------------------------------
            # BULLISH OB
            # Zona: low .. high
            # ------------------------------------------------------
            if ($type eq 'BULLISH_OB') {

                # La vela entra en la banda.
                if (
                    defined $low
                    && $low <= $ob_bar->{high}
                    && $low >= $ob_bar->{low}
                ) {
                    $touched = 1;
                    $first_touch_index //= $i;
                }

                my $mitigation_value =
                    $mitigation_source eq 'CLOSE'
                        ? $close
                        : $low;

                # Invalida al atravesar el extremo inferior.
                if (
                    defined $mitigation_value
                    && $mitigation_value < $ob_bar->{low}
                ) {
                    $touched = 1;
                    $first_touch_index //= $i;

                    $invalidated = 1;
                    $invalidated_index = $i;

                    last;
                }
            }

            # ------------------------------------------------------
            # BEARISH OB
            # Zona: low .. high
            # ------------------------------------------------------
            elsif ($type eq 'BEARISH_OB') {

                if (
                    defined $high
                    && $high >= $ob_bar->{low}
                    && $high <= $ob_bar->{high}
                ) {
                    $touched = 1;
                    $first_touch_index //= $i;
                }

                my $mitigation_value =
                    $mitigation_source eq 'CLOSE'
                        ? $close
                        : $high;

                # Invalida al atravesar el extremo superior.
                if (
                    defined $mitigation_value
                    && $mitigation_value > $ob_bar->{high}
                ) {
                    $touched = 1;
                    $first_touch_index //= $i;

                    $invalidated = 1;
                    $invalidated_index = $i;

                    last;
                }
            }
        }

        push @order_blocks, {
            type => $type,
            mode => $self->{mode},

            # internal o external según el motor que lo calculó.
            tier => $self->{mode},

            index       => $ob_index,
            left_index  => $ob_index,
            break_index => $break_index,

            right_index => defined $invalidated_index
                ? $invalidated_index
                : $last_index,

            top    => $ob_bar->{high},
            bottom => $ob_bar->{low},

            touched          => $touched,
            first_touch_index => $first_touch_index,

            invalidated       => $invalidated,
            invalidated_index => $invalidated_index,

            # En esta implementación, un OB se considera mitigado
            # cuando el precio vuelve a tocar su zona.
            mitigated       => $touched,
            mitigated_index => $first_touch_index,

            active => $invalidated ? 0 : 1,

            mitigation_source => $mitigation_source,

            source_event => $raw_type,
            source       => 'LUXALGO_ORDER_BLOCK',
        };
    }
    my $active_count = grep {
    $_
    && ref($_) eq 'HASH'
    && $_->{active}
    } @order_blocks;

    my $invalidated_count = grep {
        $_
        && ref($_) eq 'HASH'
        && $_->{invalidated}
    } @order_blocks;

    my $bullish_count = grep {
        $_
        && ref($_) eq 'HASH'
        && ($_->{type} // '') eq 'BULLISH_OB'
    } @order_blocks;

    my $bearish_count = grep {
        $_
        && ref($_) eq 'HASH'
        && ($_->{type} // '') eq 'BEARISH_OB'
    } @order_blocks;

    print STDERR
        "[OB AUDIT] mode=" . ($self->{mode} // 'unknown')
        . " total=" . scalar(@order_blocks)
        . " active=$active_count"
        . " invalidated=$invalidated_count"
        . " bullish=$bullish_count"
        . " bearish=$bearish_count"
        . " until=$last_index\n";


    return \@order_blocks;
}


1;