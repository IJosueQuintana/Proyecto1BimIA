package Market::ML::SequentialFeatureExtractor;

use strict;
use warnings;
use List::Util qw(sum min max);
use Market::ML::SequentialFeatureSchema;

sub new {
    my ($class, %args) = @_;
    return bless {
        symbol    => $args{symbol} // 'MARKET',
        timeframe => $args{timeframe} // 1,
    }, $class;
}

sub feature_names { return Market::ML::SequentialFeatureSchema->feature_columns; }

sub extract {
    my ($self, %args) = @_;
    my $candles = $args{candles} // [];
    my $atr = $args{atr} // [];
    my $liquidity = $args{liquidity} // [];
    my $events = $args{structure_events} // [];
    my $fvg = $args{fvg_levels} // [];
    my $obs = $args{order_blocks} // [];
    die "candles debe ser ARRAY\n" if ref($candles) ne 'ARRAY';

    my @liq = sort { _created($a) <=> _created($b) } grep { ref($_) eq 'HASH' && defined $_->{price} } @$liquidity;
    my @evt = sort { _event_index($a) <=> _event_index($b) } grep { ref($_) eq 'HASH' } @$events;
    my @fvg = sort { _created($a) <=> _created($b) } grep { ref($_) eq 'HASH' && defined $_->{top} && defined $_->{bottom} } @$fvg;
    my @obs = sort { _created($a) <=> _created($b) } grep { ref($_) eq 'HASH' && defined $_->{top} && defined $_->{bottom} } @$obs;

    my @rows;
    my ($last_event_idx, $last_event_code) = (undef, 0);
    my $event_cursor = 0;

    for my $i (0 .. $#$candles) {
        my $c = $candles->[$i];
        my $a = _num($atr->[$i]);
        next if !$a || $i < 20;

        while ($event_cursor < @evt && _event_index($evt[$event_cursor]) <= $i) {
            $last_event_idx = _event_index($evt[$event_cursor]);
            $last_event_code = _structure_code($evt[$event_cursor]);
            $event_cursor++;
        }

        my ($bsl_dist, $ssl_dist, $bsl_count, $ssl_count) = _liquidity_features(\@liq, $c->{close}, $a, $i);
        my ($inside_fvg, $fvg_dist) = _zone_features(\@fvg, $c->{close}, $a, $i);
        my ($inside_ob, $ob_dist) = _zone_features(\@obs, $c->{close}, $a, $i);
        my $mean20 = _mean_close($candles, $i, 20);
        my $vol_mean20 = _mean_field($candles, $i - 1, 20, 'volume');
        my $vol_sd20 = _stdev_field($candles, $i - 1, 20, 'volume');

        push @rows, {
            symbol => $args{symbol} // $self->{symbol}, timeframe => $args{timeframe} // $self->{timeframe},
            candle_index => $i, timestamp => $c->{time} // '', epoch => $c->{epoch} // '',
            return_1 => _ret($candles, $i, 1), return_3 => _ret($candles, $i, 3), return_5 => _ret($candles, $i, 5),
            range_atr => ($c->{high} - $c->{low}) / $a,
            body_atr => abs($c->{close} - $c->{open}) / $a,
            upper_wick_atr => ($c->{high} - max($c->{open}, $c->{close})) / $a,
            lower_wick_atr => (min($c->{open}, $c->{close}) - $c->{low}) / $a,
            close_position => ($c->{high} > $c->{low}) ? (($c->{close} - $c->{low}) / ($c->{high} - $c->{low})) : 0.5,
            volatility_10 => _return_stdev($candles, $i, 10), volatility_20 => _return_stdev($candles, $i, 20),
            volume_zscore => $vol_sd20 > 0 ? (($c->{volume} - $vol_mean20) / $vol_sd20) : 0,
            volume_ratio => $vol_mean20 > 0 ? ($c->{volume} / $vol_mean20) : 1,
            slope_10 => _slope($candles, $i, 10) / $a, slope_20 => _slope($candles, $i, 20) / $a,
            price_vs_mean_20_atr => ($c->{close} - $mean20) / $a,
            distance_to_bsl_atr => $bsl_dist, distance_to_ssl_atr => $ssl_dist,
            active_bsl_count => $bsl_count, active_ssl_count => $ssl_count,
            liquidity_imbalance => ($bsl_count + $ssl_count) ? (($bsl_count - $ssl_count) / ($bsl_count + $ssl_count)) : 0,
            inside_fvg => $inside_fvg, distance_fvg_atr => $fvg_dist,
            inside_order_block => $inside_ob, distance_ob_atr => $ob_dist,
            bars_since_structure_event => defined($last_event_idx) ? $i - $last_event_idx : -1,
            last_structure_event => $last_event_code,
        };
    }
    return \@rows;
}

sub _liquidity_features {
    my ($levels, $price, $atr, $i) = @_;
    my (@bsl, @ssl);
    for my $l (@$levels) {
        next if _created($l) > $i;
        my $end = _end_index($l);
        next if defined($end) && $end < $i;
        my $type = uc($l->{type} // '');
        push @bsl, $l->{price} if $type eq 'BSL' && $l->{price} >= $price;
        push @ssl, $l->{price} if $type eq 'SSL' && $l->{price} <= $price;
    }
    my $bd = @bsl ? (min(@bsl) - $price) / $atr : -1;
    my $sd = @ssl ? ($price - max(@ssl)) / $atr : -1;
    return ($bd, $sd, scalar(@bsl), scalar(@ssl));
}

sub _zone_features {
    my ($zones, $price, $atr, $i) = @_;
    my ($inside, $best) = (0, undef);
    for my $z (@$zones) {
        next if _created($z) > $i;
        my $end = _end_index($z);
        next if defined($end) && $end < $i;
        my ($lo, $hi) = (min($z->{bottom}, $z->{top}), max($z->{bottom}, $z->{top}));
        if ($price >= $lo && $price <= $hi) { $inside = 1; $best = 0; last; }
        my $d = $price < $lo ? $lo - $price : $price - $hi;
        $best = $d if !defined($best) || $d < $best;
    }
    return ($inside, defined($best) ? $best / $atr : -1);
}

sub _ret { my ($c,$i,$n)=@_; return 0 if $i<$n || !$c->[$i-$n]{close}; return ($c->[$i]{close}-$c->[$i-$n]{close})/$c->[$i-$n]{close}; }
sub _mean_close { return _mean_field($_[0], $_[1], $_[2], 'close'); }
sub _mean_field { my ($c,$end,$n,$f)=@_; my $s=$end-$n+1; $s=0 if $s<0; my @v=map{_num($c->[$_]{$f})}$s..$end; return @v ? sum(@v)/@v : 0; }
sub _stdev_field { my ($c,$end,$n,$f)=@_; my $s=$end-$n+1; $s=0 if $s<0; my @v=map{_num($c->[$_]{$f})}$s..$end; return 0 if @v<2; my $m=sum(@v)/@v; return sqrt(sum(map{($_-$m)**2}@v)/(@v-1)); }
sub _return_stdev { my ($c,$i,$n)=@_; my @v=map{_ret($c,$_ ,1)}($i-$n+1)..$i; my $m=sum(@v)/@v; return sqrt(sum(map{($_-$m)**2}@v)/(@v-1)); }
sub _slope { my ($c,$i,$n)=@_; my $s=$i-$n+1; my ($sx,$sy,$sxy,$sx2)=(0,0,0,0); for my $k(0..$n-1){my $y=$c->[$s+$k]{close};$sx+=$k;$sy+=$y;$sxy+=$k*$y;$sx2+=$k*$k;} my $d=$n*$sx2-$sx*$sx; return $d ? ($n*$sxy-$sx*$sy)/$d : 0; }
sub _created { my ($x)=@_; return $x->{break_index} // $x->{confirmed_index} // $x->{index2} // $x->{index} // $x->{created_index} // 0; }
sub _end_index { my ($x)=@_; return $x->{invalidated_index} // $x->{mitigated_index} // $x->{resolved_index} // $x->{swept_index}; }
sub _event_index { my ($x)=@_; return $x->{break_index} // $x->{index} // $x->{confirmation_index} // 0; }
sub _structure_code {
    my ($x)=@_;
    my $t=uc($x->{raw_type} // $x->{type} // $x->{event} // '');
    return  1 if $t =~ /BOS[_-]?(?:UP|BULL)/ || $t =~ /(?:UP|BULL)[_-]?BOS/;
    return -1 if $t =~ /BOS[_-]?(?:DOWN|BEAR)/ || $t =~ /(?:DOWN|BEAR)[_-]?BOS/;
    return  2 if $t =~ /CHOCH[_-]?(?:UP|BULL)/ || $t =~ /(?:UP|BULL)[_-]?CHOCH/;
    return -2 if $t =~ /CHOCH[_-]?(?:DOWN|BEAR)/ || $t =~ /(?:DOWN|BEAR)[_-]?CHOCH/;
    return 0;
}
sub _num { return defined($_[0]) && $_[0] =~ /^-?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$/ ? 0+$_[0] : 0; }
1;
