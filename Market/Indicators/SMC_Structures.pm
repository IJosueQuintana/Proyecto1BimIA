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
        break_source   => $args{break_source}   // 'close',
        prefix         => $args{prefix} // '',
        mode           => $args{mode}   // 'external',
        audit => {pivots => [], labels => [], bos => [], choch => [],},
        swing_length => $args{swing_length} // 50,
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

sub _make_structure_event {
    my ($self, %args) = @_;

    my $raw_type = $args{raw_type};

    return {
        type     => $self->{prefix} . $raw_type,
        raw_type => $raw_type,
        mode     => $self->{mode},

        index       => $args{break_index},
        break_index => $args{break_index},
        break_price => $args{break_price},

        pivot_index => $args{pivot}->{index},
        pivot_price => $args{pivot}->{price},

        price       => $args{pivot}->{price},
        pivot       => $args{pivot}->{label},

        trigger_pivot_index => $args{trigger_pivot}->{index}  // undef,
        trigger_pivot_label => $args{trigger_label}           // undef,

        trend_after => $args{trend_after},
        break_size  => abs($args{break_price} - $args{pivot}->{price}),
    };
}

sub _scan_structure_breaks {
    my ($self, %args) = @_;

    my $market       = $args{market};
    my $from         = $args{from};
    my $to           = $args{to};
    my $active_high  = $args{active_high_ref};
    my $active_low   = $args{active_low_ref};
    my $trend_ref    = $args{trend_ref};
    my $events_ref   = $args{events_ref};
    my $pivot        = $args{trigger_pivot};
    my $label        = $args{trigger_label};

    return if !$market;
    return if !defined $from || !defined $to;
    return if $to < $from;

    my $candles = $market->get_slice($from - 1, $to);
    return if !$candles || @$candles < 2;

    for my $local_i (1 .. $#$candles) {
        my $global_i = ($from - 1) + $local_i;

        my $prev_bar = $candles->[$local_i - 1];
        my $bar      = $candles->[$local_i];

        next if !$prev_bar || !$bar;

        my $prev_close = $prev_bar->{close};
        my $close      = $bar->{close};

        next if !defined $prev_close || !defined $close;

        # ==============================
        # BOS / CHoCH alcista
        # Equivalente a ta.crossover(close, highActivo)
        # ==============================
        if (
            defined $$active_high
            && !$$active_high->{crossed}
            && defined $$active_high->{price}
            && $global_i > $$active_high->{index}
        ) {
            my $level = $$active_high->{price};

            my $cross_up =
                $prev_close <= $level
                &&
                $close > $level;

            if ($cross_up) {
                my $raw_type = ($$trend_ref eq 'DOWN')
                    ? 'CHoCH_UP'
                    : 'BOS_UP';

                my $event = $self->_make_structure_event(
                    raw_type       => $raw_type,
                    break_index    => $global_i,
                    break_price    => $close,
                    pivot          => $$active_high,
                    trigger_pivot  => $pivot // {},
                    trigger_label  => $label,
                    trend_after    => 'UP',
                );

                $event->{direction} = 'bullish';
                $event->{side}      = 'bullish';
                $event->{label}     = $raw_type =~ /CHoCH/ ? 'CHoCH' : 'BOS';

                push @{$self->{events}}, $event;
                push @$events_ref, $raw_type if $events_ref;

                if ($raw_type =~ /BOS/) {
                    push @{$self->{audit}->{bos}}, $event;
                }
                elsif ($raw_type =~ /CHoCH/) {
                    push @{$self->{audit}->{choch}}, $event;
                }

                $$active_high->{crossed} = 1;
                $$trend_ref = 'UP';
            }
        }

        # ==============================
        # BOS / CHoCH bajista
        # Equivalente a ta.crossunder(close, lowActivo)
        # ==============================
        if (
            defined $$active_low
            && !$$active_low->{crossed}
            && defined $$active_low->{price}
            && $global_i > $$active_low->{index}
        ) {
            my $level = $$active_low->{price};

            my $cross_down =
                $prev_close >= $level
                &&
                $close < $level;

            if ($cross_down) {
                my $raw_type = ($$trend_ref eq 'UP')
                    ? 'CHoCH_DOWN'
                    : 'BOS_DOWN';

                my $event = $self->_make_structure_event(
                    raw_type       => $raw_type,
                    break_index    => $global_i,
                    break_price    => $close,
                    pivot          => $$active_low,
                    trigger_pivot  => $pivot // {},
                    trigger_label  => $label,
                    trend_after    => 'DOWN',
                );

                $event->{direction} = 'bearish';
                $event->{side}      = 'bearish';
                $event->{label}     = $raw_type =~ /CHoCH/ ? 'CHoCH' : 'BOS';

                push @{$self->{events}}, $event;
                push @$events_ref, $raw_type if $events_ref;

                if ($raw_type =~ /BOS/) {
                    push @{$self->{audit}->{bos}}, $event;
                }
                elsif ($raw_type =~ /CHoCH/) {
                    push @{$self->{audit}->{choch}}, $event;
                }

                $$active_low->{crossed} = 1;
                $$trend_ref = 'DOWN';
            }
        }
    }
}

sub calculate {
    my ($self, $pivots_ignored, $market) = @_;

    $self->{structure} = [];
    $self->{events}    = [];
    $self->{audit}     = {
        labels => [],
        bos    => [],
        choch  => [],
    };

    return {
        structure    => [],
        events       => [],
        fvg          => [],
        order_blocks => [],
        audit        => $self->{audit},
    } if !$market;

    my $last_index = $market->last_index();

    my $candles = $market->get_slice(0, $last_index);
    return {
        structure    => [],
        events       => [],
        fvg          => [],
        order_blocks => [],
        audit        => $self->{audit},
    } if !$candles || @$candles < 10;

    my $size = $self->{mode} eq 'internal'
        ? 5
        : ($self->{swing_length} // 50);

    my $leg_state = 0;
    my $prev_leg_state;

    my $last_high;
    my $last_low;

    my $active_high;
    my $active_low;

    my $trend = 0; # 1 bullish, -1 bearish, 0 unknown

    for my $i (0 .. $#$candles) {
        my $bar = $candles->[$i];
        next if !$bar;

        # ==============================
        # 1. Detectar pivote estilo LuxAlgo
        # ==============================
        if ($i >= $size) {
            my $pivot_i = $i - $size;
            my $pivot_bar = $candles->[$pivot_i];

            my $highest_after = $candles->[$i - $size + 1]{high};
            my $lowest_after  = $candles->[$i - $size + 1]{low};

            for my $j ($i - $size + 1 .. $i) {
                $highest_after = $candles->[$j]{high}
                    if $candles->[$j]{high} > $highest_after;

                $lowest_after = $candles->[$j]{low}
                    if $candles->[$j]{low} < $lowest_after;
            }

            my $new_high = $pivot_bar->{high} > $highest_after;
            my $new_low  = $pivot_bar->{low}  < $lowest_after;

            $prev_leg_state = $leg_state;

            if ($new_high) {
                $leg_state = 0; # bearish leg
            }
            elsif ($new_low) {
                $leg_state = 1; # bullish leg
            }

            my $changed = defined $prev_leg_state && $leg_state != $prev_leg_state;

            if ($changed) {

                # startOfBearishLeg => HIGH pivot
                if ($prev_leg_state == 1 && $leg_state == 0) {
                    my $label = !defined $last_high
                        ? 'H'
                        : ($pivot_bar->{high} > $last_high->{price} ? 'HH' : 'LH');

                    my $pivot = {
                        type      => 'HIGH',
                        index     => $pivot_i,
                        price     => $pivot_bar->{high},
                        label     => $self->{prefix} . $label,
                        raw_label => $label,
                        mode      => $self->{mode},
                        source    => $self->{mode} eq 'internal' ? 'LuxAlgoInternal5' : 'LuxAlgoSwing',
                        crossed   => 0,
                    };

                    $last_high   = $pivot;
                    $active_high = { %$pivot, crossed => 0 };

                    push @{$self->{structure}}, $pivot;
                    push @{$self->{audit}->{labels}}, $pivot;
                }

                # startOfBullishLeg => LOW pivot
                elsif ($prev_leg_state == 0 && $leg_state == 1) {
                    my $label = !defined $last_low
                        ? 'L'
                        : ($pivot_bar->{low} > $last_low->{price} ? 'HL' : 'LL');

                    my $pivot = {
                        type      => 'LOW',
                        index     => $pivot_i,
                        price     => $pivot_bar->{low},
                        label     => $self->{prefix} . $label,
                        raw_label => $label,
                        mode      => $self->{mode},
                        source    => $self->{mode} eq 'internal' ? 'LuxAlgoInternal5' : 'LuxAlgoSwing',
                        crossed   => 0,
                    };

                    $last_low   = $pivot;
                    $active_low = { %$pivot, crossed => 0 };

                    push @{$self->{structure}}, $pivot;
                    push @{$self->{audit}->{labels}}, $pivot;
                }
            }
        }

        # ==============================
        # 2. Detectar BOS / CHoCH con crossover real
        # ==============================
        next if $i == 0;

        my $prev_close = $candles->[$i - 1]{close};
        my $close      = $bar->{close};

        next if !defined $prev_close || !defined $close;

        # Bullish BOS / CHoCH
        if (
            defined $active_high
            && !$active_high->{crossed}
            && $i > $active_high->{index}
            && $prev_close <= $active_high->{price}
            && $close > $active_high->{price}
        ) {
            my $raw_type = $trend == -1 ? 'CHoCH_UP' : 'BOS_UP';

            my $event = {
                type        => $self->{prefix} . $raw_type,
                raw_type    => $raw_type,
                mode        => $self->{mode},

                index       => $i,
                break_index => $i,
                break_price => $close,

                pivot_index => $active_high->{index},
                pivot_price => $active_high->{price},
                price       => $active_high->{price},
                pivot       => $active_high->{label},

                direction   => 'bullish',
                side        => 'bullish',
                label       => $raw_type =~ /CHoCH/ ? 'CHoCH' : 'BOS',
                trend_after => 'UP',
                break_size  => abs($close - $active_high->{price}),
            };

            push @{$self->{events}}, $event;

            if ($raw_type =~ /BOS/) {
                push @{$self->{audit}->{bos}}, $event;
            } else {
                push @{$self->{audit}->{choch}}, $event;
            }

            $active_high->{crossed} = 1;
            $trend = 1;
        }

        # Bearish BOS / CHoCH
        if (
            defined $active_low
            && !$active_low->{crossed}
            && $i > $active_low->{index}
            && $prev_close >= $active_low->{price}
            && $close < $active_low->{price}
        ) {
            my $raw_type = $trend == 1 ? 'CHoCH_DOWN' : 'BOS_DOWN';

            my $event = {
                type        => $self->{prefix} . $raw_type,
                raw_type    => $raw_type,
                mode        => $self->{mode},

                index       => $i,
                break_index => $i,
                break_price => $close,

                pivot_index => $active_low->{index},
                pivot_price => $active_low->{price},
                price       => $active_low->{price},
                pivot       => $active_low->{label},

                direction   => 'bearish',
                side        => 'bearish',
                label       => $raw_type =~ /CHoCH/ ? 'CHoCH' : 'BOS',
                trend_after => 'DOWN',
                break_size  => abs($close - $active_low->{price}),
            };

            push @{$self->{events}}, $event;

            if ($raw_type =~ /BOS/) {
                push @{$self->{audit}->{bos}}, $event;
            } else {
                push @{$self->{audit}->{choch}}, $event;
            }

            $active_low->{crossed} = 1;
            $trend = -1;
        }
    }

    my $last_pivot_index = @{$self->{structure}}
        ? $self->{structure}->[-1]{index}
        : undef;

    $self->{fvg} = $self->_detect_fvg($market, $last_pivot_index);
    $self->{order_blocks} = $self->_detect_order_blocks($market);
    $self->{audit}->{event_health} = $self->_audit_events_health();

    return {
        structure     => $self->{structure},
        events        => $self->{events},
        fvg           => $self->{fvg},
        order_blocks  => $self->{order_blocks},
        state         => $self->{state},
        audit         => $self->{audit},
    };
}


sub _detect_fvg {
    my ($self, $market, $last_index) = @_;

    my @fvg;
    return \@fvg if !$market || !defined $last_index || $last_index < 10;

    my $candles = $market->get_slice(0, $last_index);
    return \@fvg if !$candles || @$candles < 10;

    # ATR simple interno para filtrar FVG pequeños
    my @atr;
    my $atr_period = 14;

    for my $i (0 .. $#$candles) {
        my $bar = $candles->[$i];
        next if !$bar;

        my $prev_close = $i > 0 ? $candles->[$i - 1]{close} : $bar->{close};

        my $tr1 = ($bar->{high} // 0) - ($bar->{low} // 0);
        my $tr2 = abs(($bar->{high} // 0) - ($prev_close // 0));
        my $tr3 = abs(($bar->{low}  // 0) - ($prev_close // 0));

        my $tr = $tr1;
        $tr = $tr2 if $tr2 > $tr;
        $tr = $tr3 if $tr3 > $tr;

        my $from = $i - $atr_period + 1;
        $from = 0 if $from < 0;

        my $sum = 0;
        my $n   = 0;

        for my $j ($from .. $i) {
            my $b = $candles->[$j];
            next if !$b;

            my $pc = $j > 0 ? $candles->[$j - 1]{close} : $b->{close};

            my $a = ($b->{high} // 0) - ($b->{low} // 0);
            my $b1 = abs(($b->{high} // 0) - ($pc // 0));
            my $b2 = abs(($b->{low}  // 0) - ($pc // 0));

            my $local_tr = $a;
            $local_tr = $b1 if $b1 > $local_tr;
            $local_tr = $b2 if $b2 > $local_tr;

            $sum += $local_tr;
            $n++;
        }

        $atr[$i] = $n ? $sum / $n : $tr;
    }

    for my $i (3 .. $#$candles) {

        my $c1 = $candles->[$i - 1];
        my $c2 = $candles->[$i - 2]; # vela impulsiva central
        my $c3 = $candles->[$i - 3];

        next if !$c1 || !$c2 || !$c3;

        my $atr_i = $atr[$i] // 1;
        $atr_i = 1 if $atr_i <= 0;

        my $body_c2 = abs(($c2->{close} // 0) - ($c2->{open} // 0));

        # ==========================================================
        # Bullish FVG: high[3] < low[1] + impulso alcista suficiente
        # ==========================================================
        if (
            defined $c3->{high}
            && defined $c1->{low}
            && $c3->{high} < $c1->{low}
        ) {
            my $top    = $c1->{low};
            my $bottom = $c3->{high};
            my $gap    = abs($top - $bottom);

            next if $gap < $atr_i * 0.25;
            next if $body_c2 < $atr_i * 0.45;
            next if !defined $c2->{open} || !defined $c2->{close};
            next if $c2->{close} <= $c2->{open};

            my $mitigated_index;
            my $partial = 0;

            for my $j ($i .. $#$candles) {
                my $bar = $candles->[$j];
                next if !$bar;

                if (defined $bar->{low} && $bar->{low} < $top) {
                    $partial = 1;
                }

                if (defined $bar->{low} && $bar->{low} <= $bottom) {
                    $mitigated_index = $j;
                    last;
                }
            }

            push @fvg, {
                type        => 'BULLISH_FVG',
                mode        => $self->{mode},
                index       => $i,
                left_index  => $i - 2,
                right_index => defined $mitigated_index ? $mitigated_index : $last_index,
                top         => $top,
                bottom      => $bottom,
                gap         => $gap,
                atr         => $atr_i,
                mitigated   => defined $mitigated_index ? 1 : 0,
                partial     => $partial,
            };
        }

        # ==========================================================
        # Bearish FVG: low[3] > high[1] + impulso bajista suficiente
        # ==========================================================
        if (
            defined $c3->{low}
            && defined $c1->{high}
            && $c3->{low} > $c1->{high}
        ) {
            my $top    = $c3->{low};
            my $bottom = $c1->{high};
            my $gap    = abs($top - $bottom);

            next if $gap < $atr_i * 0.25;
            next if $body_c2 < $atr_i * 0.45;
            next if !defined $c2->{open} || !defined $c2->{close};
            next if $c2->{close} >= $c2->{open};

            my $mitigated_index;
            my $partial = 0;

            for my $j ($i .. $#$candles) {
                my $bar = $candles->[$j];
                next if !$bar;

                if (defined $bar->{high} && $bar->{high} > $bottom) {
                    $partial = 1;
                }

                if (defined $bar->{high} && $bar->{high} >= $top) {
                    $mitigated_index = $j;
                    last;
                }
            }

            push @fvg, {
                type        => 'BEARISH_FVG',
                mode        => $self->{mode},
                index       => $i,
                left_index  => $i - 2,
                right_index => defined $mitigated_index ? $mitigated_index : $last_index,
                top         => $top,
                bottom      => $bottom,
                gap         => $gap,
                atr         => $atr_i,
                mitigated   => defined $mitigated_index ? 1 : 0,
                partial     => $partial,
            };
        }
    }

    return \@fvg;
}

sub _detect_order_blocks {
    my ($self, $market) = @_;

    my @obs;
    return \@obs if !$market;

    my $last_index = $market->last_index();

    for my $e (@{$self->{events} || []}) {

        my $from = $e->{pivot_index};
        my $to   = $e->{break_index} // $e->{index};

        next if !defined $from || !defined $to || $to <= $from;

        my $candles = $market->get_slice($from, $to);
        next if !$candles || !@$candles;

        my $ob_local;

        # Bullish OB = última vela bajista antes del rompimiento alcista
        if (($e->{raw_type} // '') =~ /UP/) {

            for (my $j = $#$candles - 1; $j >= 0; $j--) {
                my $bar = $candles->[$j];
                next if !$bar;

                if (defined $bar->{open} && defined $bar->{close} && $bar->{close} < $bar->{open}) {
                    $ob_local = $j;
                    last;
                }
            }

            $ob_local = 0 if !defined $ob_local;

            my $global_i = $from + $ob_local;
            my $bar = $candles->[$ob_local];

            my $invalidated_index;
            my $future = $market->get_slice($to, $last_index);

            for my $k (0 .. $#$future) {
                my $b = $future->[$k];
                next if !$b;

                if (defined $b->{close} && $b->{close} < $bar->{low}) {
                    $invalidated_index = $to + $k;
                    last;
                }
            }

            push @obs, {
                type        => 'BULLISH_OB',
                mode        => $self->{mode},
                index       => $global_i,
                break_index => defined $invalidated_index ? $invalidated_index : $last_index,
                top         => $bar->{high},
                bottom      => $bar->{low},
                source      => $e->{raw_type},
                invalidated => defined $invalidated_index ? 1 : 0,
            };
        }

        # Bearish OB = última vela alcista antes del rompimiento bajista
        elsif (($e->{raw_type} // '') =~ /DOWN/) {

            for (my $j = $#$candles - 1; $j >= 0; $j--) {
                my $bar = $candles->[$j];
                next if !$bar;

                if (defined $bar->{open} && defined $bar->{close} && $bar->{close} > $bar->{open}) {
                    $ob_local = $j;
                    last;
                }
            }

            $ob_local = 0 if !defined $ob_local;

            my $global_i = $from + $ob_local;
            my $bar = $candles->[$ob_local];

            my $invalidated_index;
            my $future = $market->get_slice($to, $last_index);

            for my $k (0 .. $#$future) {
                my $b = $future->[$k];
                next if !$b;

                if (defined $b->{close} && $b->{close} > $bar->{high}) {
                    $invalidated_index = $to + $k;
                    last;
                }
            }

            push @obs, {
                type        => 'BEARISH_OB',
                mode        => $self->{mode},
                index       => $global_i,
                break_index => defined $invalidated_index ? $invalidated_index : $last_index,
                top         => $bar->{high},
                bottom      => $bar->{low},
                source      => $e->{raw_type},
                invalidated => defined $invalidated_index ? 1 : 0,
            };
        }
    }

    return \@obs;
}


1;