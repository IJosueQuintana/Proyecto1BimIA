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
        audit => {pivots => [], labels => [], bos => [], choch => [],},
        
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

sub calculate {
    my ($self, $pivots, $market) = @_;

    $self->{pivots}    = $pivots;
    $self->{structure} = [];
    $self->{events}    = [];
    $self->{audit}     = {
        labels => [],
        bos    => [],
        choch  => [],
    };

    my $last_high;
    my $last_low;

    my $trend = 'UNKNOWN';

    my $active_high;
    my $active_low;

    my $last_scan_index = undef;

    for my $pivot (@$pivots) {

        my $label;

        if ($pivot->{type} eq 'HIGH') {
            $label = !defined $last_high
                ? 'H'
                : ($pivot->{price} > $last_high->{price} ? 'HH' : 'LH');

            $last_high = $pivot;
        }
        elsif ($pivot->{type} eq 'LOW') {
            $label = !defined $last_low
                ? 'L'
                : ($pivot->{price} > $last_low->{price} ? 'HL' : 'LL');

            $last_low = $pivot;
        }
        else {
            next;
        }

        my @events_this_pivot;

        # 1. Escanear vela por vela desde el último pivote procesado
        if (defined $market && defined $last_scan_index) {

            my $from = $last_scan_index + 1;
            my $to   = $pivot->{index};

            if ($to >= $from) {

                my $candles = $market->get_slice($from, $to);

                for my $local_i (0 .. $#$candles) {

                    my $global_i = $from + $local_i;
                    my $bar      = $candles->[$local_i];
                    my $close    = $bar->{close};

                    # Ruptura alcista de nivel HIGH activo
                    if (
                        defined $active_high
                        && !$active_high->{crossed}
                        && defined $close
                        && $close > $active_high->{price}
                    ) {
                        my $event = ($trend eq 'DOWN')
                            ? 'CHoCH_UP'
                            : 'BOS_UP';

                        my $event_record = {
                            type     => $self->{prefix} . $event,
                            raw_type => $event,
                            mode     => $self->{mode},

                            index       => $global_i,
                            break_index => $global_i,
                            break_price => $close,

                            pivot_index => $active_high->{index},
                            pivot_price => $active_high->{price},

                            price       => $active_high->{price},
                            pivot       => $active_high->{label},

                            trigger_pivot_index => $pivot->{index},
                            trigger_pivot_label => $label,

                            trend_after => 'UP',
                            break_size  => $close - $active_high->{price},
                        };

                        push @{$self->{events}}, $event_record;
                        push @events_this_pivot, $event;

                        if ($event =~ /BOS/) {
                            push @{$self->{audit}->{bos}}, $event_record;
                        }
                        elsif ($event =~ /CHoCH/) {
                            push @{$self->{audit}->{choch}}, $event_record;
                        }

                        $active_high->{crossed} = 1;
                        $trend = 'UP';
                    }

                    # Ruptura bajista de nivel LOW activo
                    if (
                        defined $active_low
                        && !$active_low->{crossed}
                        && defined $close
                        && $close < $active_low->{price}
                    ) {
                        my $event = ($trend eq 'UP')
                            ? 'CHoCH_DOWN'
                            : 'BOS_DOWN';

                        my $event_record = {
                            type     => $self->{prefix} . $event,
                            raw_type => $event,
                            mode     => $self->{mode},

                            index       => $global_i,
                            break_index => $global_i,
                            break_price => $close,

                            pivot_index => $active_low->{index},
                            pivot_price => $active_low->{price},

                            price       => $active_low->{price},
                            pivot       => $active_low->{label},

                            trigger_pivot_index => $pivot->{index},
                            trigger_pivot_label => $label,

                            trend_after => 'DOWN',
                            break_size  => $active_low->{price} - $close,
                        };

                        push @{$self->{events}}, $event_record;
                        push @events_this_pivot, $event;

                        if ($event =~ /BOS/) {
                            push @{$self->{audit}->{bos}}, $event_record;
                        }
                        elsif ($event =~ /CHoCH/) {
                            push @{$self->{audit}->{choch}}, $event_record;
                        }

                        $active_low->{crossed} = 1;
                        $trend = 'DOWN';
                    }
                }
            }
        }

        # 2. Actualizar nivel activo DESPUÉS de revisar rupturas
        if ($pivot->{type} eq 'HIGH') {
            $active_high = {
                %$pivot,
                label   => $label,
                crossed => 0,
            };
        }
        elsif ($pivot->{type} eq 'LOW') {
            $active_low = {
                %$pivot,
                label   => $label,
                crossed => 0,
            };
        }

        my $event_for_structure = @events_this_pivot
            ? join(',', @events_this_pivot)
            : undef;

        push @{$self->{audit}->{labels}}, {
            index  => $pivot->{index},
            type   => $pivot->{type},
            price  => $pivot->{price},
            label  => $label,
            mode   => $self->{mode},
            source => $pivot->{source} // 'ATR',
            event  => $event_for_structure,
            trend  => $trend,
        };

        my $final_label = $self->{prefix} . $label;

        push @{$self->{structure}}, {
            %$pivot,
            label     => $final_label,
            raw_label => $label,
            mode      => $self->{mode},
            event     => $event_for_structure,
        };

        $last_scan_index = $pivot->{index};
    }

    my $last_index = @$pivots ? $pivots->[-1]{index} : undef;

$self->{fvg} = $self->_detect_fvg($market, $last_index);
$self->{order_blocks} = $self->_detect_order_blocks($market);

    $self->{audit}->{event_health} = $self->_audit_events_health();

    if ($self->{debug_audit}) {
    print "\n---- SMC EVENT HEALTH ------------\n";
    print "BOS direction errors     : $self->{audit}->{event_health}->{bos_direction_errors}\n";
    print "CHoCH direction errors   : $self->{audit}->{event_health}->{choch_direction_errors}\n";
    print "Break price errors       : $self->{audit}->{event_health}->{break_price_errors}\n";
    print "Duplicate event errors   : $self->{audit}->{event_health}->{duplicate_event_errors}\n";
    print "Long event warnings      : $self->{audit}->{event_health}->{long_event_warnings}\n";
    print "----------------------------------\n";
}

    return {
    structure    => $self->{structure},
    events       => $self->{events},
    fvg          => $self->{fvg},
    order_blocks => $self->{order_blocks},
    state        => $self->{state},
    audit        => $self->{audit},
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