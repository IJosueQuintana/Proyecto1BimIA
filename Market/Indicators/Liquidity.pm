package Market::Indicators::Liquidity;

use strict;
use warnings;

sub new {
    my ($class, %args) = @_;

    my $self = {
        atr_mult         => $args{atr_mult}         // 4.0,
        minor_atr_mult   => $args{minor_atr_mult}   // 1.5,
        volume_lookback      => $args{volume_lookback}      // 20,
        volume_mult          => $args{volume_mult}          // 2.8,
        volume_range_atr_min => $args{volume_range_atr_min} // 1.2,
        volume_react_mult    => $args{volume_react_mult}    // 1.5,
        min_swing_atr_mult   => $args{min_swing_atr_mult}   // 2.0,
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
        internal_structure      => [],
        external_structure      => [],
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

    $self->{clean_volume_swings} = [];
    $self->{structural_pivots_clean} = [];
    $self->{internal_structure}      = [];
    $self->{external_structure}      = [];
    $self->{structural_pivots_clean} = [];
    $self->{audit}->{pivots} = [];
    $self->{audit}->{liquidity_classification} = {};
    }

sub calculate_until {
    my ($self, $candles, $atr_values, $until_index) = @_;

    $self->reset();

    for my $i (0 .. $until_index) {
        $self->process_bar($candles, $atr_values, $i);
    }

    $self->_detect_equal_levels();

    my @external_candidates = (
    @{$self->{pivots} || []},
    @{$self->{volume_pivots} || []},
    );

    $self->_clean_zigzag_sequence(
        \@external_candidates,
        \$self->{external_structure},
        'external'
    );

    $self->_clean_zigzag_sequence(
        $self->{minor_pivots},
        \$self->{internal_structure},
        'internal'
    );  

$self->{structural_pivots_clean} = $self->{external_structure};

    $self->_clean_structural_sequence();

   if ($self->{debug_audit}) {
    $self->audit_volume_pivots($candles, 20800, 21000);
    $self->audit_clean_volume_sequence($candles, 20800, 21000);
    $self->audit_liquidity_classification($candles);
}

    return {
        pivots                   => $self->{pivots},
        structural_pivots        => $self->{external_structure},
        external_structure       => $self->{external_structure},
        internal_structure       => $self->{internal_structure},

        raw_structural_pivots    => $self->{pivots},
        raw_minor_pivots         => $self->{minor_pivots},
        minor_pivots             => $self->{internal_structure},

        volume_pivots            => $self->{volume_pivots},
        raw_structural_pivots    => $self->{pivots},
        volume_pivots            => $self->{volume_pivots},
        liquidity                => $self->{liquidity},
        events                   => $self->{events},
        equal_levels             => $self->{equal_levels},
        clean_volume_swings => $self->{clean_volume_swings},
        audit => $self->{audit},
        
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
    my ($self) = @_;

    my @recent_highs;
    my @recent_lows;

    my $lookback_pivots = 20;

    for my $p (@{$self->{minor_pivots}}) {

        my $atr = $p->{atr} // 0;
        next if $atr <= 0;

        my $tolerance = $atr * $self->{eq_tolerance};

        if ($p->{type} eq 'HIGH') {

            for my $prev (@recent_highs) {
                my $diff = abs($p->{price} - $prev->{price});

                if ($diff <= $tolerance) {
                    push @{$self->{equal_levels}}, {
                        type       => 'EQH',
                        state      => 'Detected',
                        index1     => $prev->{index},
                        index2     => $p->{index},
                        price1     => $prev->{price},
                        price2     => $p->{price},
                        price      => ($prev->{price} + $p->{price}) / 2,
                        tolerance  => $tolerance,
                        source     => 'MinorPivotHigh',
                    };
                    last;
                }
            }

            push @recent_highs, $p;
            shift @recent_highs while @recent_highs > $lookback_pivots;
        }

        elsif ($p->{type} eq 'LOW') {

            for my $prev (@recent_lows) {
                my $diff = abs($p->{price} - $prev->{price});

                if ($diff <= $tolerance) {
                    push @{$self->{equal_levels}}, {
                        type       => 'EQL',
                        state      => 'Detected',
                        index1     => $prev->{index},
                        index2     => $p->{index},
                        price1     => $prev->{price},
                        price2     => $p->{price},
                        price      => ($prev->{price} + $p->{price}) / 2,
                        tolerance  => $tolerance,
                        source     => 'MinorPivotLow',
                    };
                    last;
                }
            }

            push @recent_lows, $p;
            shift @recent_lows while @recent_lows > $lookback_pivots;
        }
    }
}

sub _update_liquidity_states {
    my ($self, $bar, $i) = @_;

    my $grab_max_bars = 3;
    my $run_bars      = $self->{confirm_bars} // 3;

    for my $lvl (@{$self->{liquidity}}) {

        next if $lvl->{state} eq 'Resolved';

        my $price = $lvl->{price};
        next if !defined $price;

        if ($lvl->{state} eq 'Detected') {

            if ($lvl->{type} eq 'BSL' && $bar->{high} > $price) {
                $lvl->{state}         = 'Swept';
                $lvl->{swept_index}   = $i;
                $lvl->{outside_count} = 0;
            }
            elsif ($lvl->{type} eq 'SSL' && $bar->{low} < $price) {
                $lvl->{state}         = 'Swept';
                $lvl->{swept_index}   = $i;
                $lvl->{outside_count} = 0;
            }
        }

        next if $lvl->{state} eq 'Detected';
        next if !defined $lvl->{swept_index};

        my $bars_after_sweep = $i - $lvl->{swept_index};

        if ($lvl->{type} eq 'BSL') {

            if ($bar->{close} < $price) {
                $lvl->{resolved_index} = $i;
                $lvl->{classification} = ($bars_after_sweep == 0)
                    ? 'Sweep'
                    : ($bars_after_sweep <= $grab_max_bars ? 'Grab' : 'Sweep');
                $lvl->{state} = 'Resolved';
                next;
            }

            if ($bar->{close} > $price) {
                $lvl->{state} = 'Acceptance';
                $lvl->{outside_count}++;

                if ($lvl->{outside_count} >= $run_bars) {
                    $lvl->{resolved_index} = $i;
                    $lvl->{classification} = 'Run';
                    $lvl->{state}          = 'Resolved';
                    next;
                }
            }
            else {
                $lvl->{outside_count} = 0;
            }
        }

        elsif ($lvl->{type} eq 'SSL') {

            if ($bar->{close} > $price) {
                $lvl->{resolved_index} = $i;
                $lvl->{classification} = ($bars_after_sweep == 0)
                    ? 'Sweep'
                    : ($bars_after_sweep <= $grab_max_bars ? 'Grab' : 'Sweep');
                $lvl->{state} = 'Resolved';
                next;
            }

            if ($bar->{close} < $price) {
                $lvl->{state} = 'Acceptance';
                $lvl->{outside_count}++;

                if ($lvl->{outside_count} >= $run_bars) {
                    $lvl->{resolved_index} = $i;
                    $lvl->{classification} = 'Run';
                    $lvl->{state}          = 'Resolved';
                    next;
                }
            }
            else {
                $lvl->{outside_count} = 0;
            }
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

    my $grab_max_bars = 3;
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

            if ($bars_after_sweep < 1 || $bars_after_sweep > $grab_max_bars) {
                $audit{grab_timing_errors}++;
                _audit_push_example(\%audit, "BAD_GRAB_TIMING", $lvl);
            }

            my $valid = 0;

            if ($type eq 'BSL') {
                $valid = (($resolved_bar->{close} // 0) < $price);
            }
            elsif ($type eq 'SSL') {
                $valid = (($resolved_bar->{close} // 0) > $price);
            }

            if (!$valid) {
                $audit{sweep_rule_errors}++;
                _audit_push_example(\%audit, "BAD_GRAB_CLOSE", $lvl);
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

1;