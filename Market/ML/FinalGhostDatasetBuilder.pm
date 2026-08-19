package Market::ML::FinalGhostDatasetBuilder;

use strict;
use warnings;
use Carp qw(croak);
use File::Basename qw(basename);
use List::Util qw(min max sum);
use Time::Piece;

use Market::ML::DatasetPipeline;
use Market::ML::FinalGhostFeatureSchema;

sub new {
    my ($class, %args) = @_;
    return bless {
        symbol   => $args{symbol} // 'NQ',
        pip_size => defined($args{pip_size}) ? 0 + $args{pip_size} : 0.25,
    }, $class;
}

sub build_file_dataset {
    my ($self, %args) = @_;
    my $file = $args{file} // croak "Debe indicar file\n";
    croak "No existe '$file'\n" if !-f $file;

    my $pipeline = Market::ML::DatasetPipeline->new(
        symbol => $self->{symbol}, timeframe => 1,
    );
    my $base = $pipeline->build_file_dataset(file => $file);
    my $candles = _load_candles($file);

    my @rows;
    my $ghost_id = 0;
    for my $row (@{$base->{rows}}) {
        my $i = $row->{confirmation_index};
        next if !defined($i) || $i < 20 || $i + 15 > $#$candles;
        my $c = $candles->[$i] or next;
        my %out = %$row;

        $ghost_id++;
        $out{ghost_id} = $ghost_id;
        $out{ghost_index} = $i;
        $out{ghost_timestamp} = $c->{time};
        $out{ghost_price_mid} = ($c->{high} + $c->{low}) / 2;
        $out{ghost_definition} = 'EXTERNAL_SWING_CONFIRMATION';
        $out{legacy_liquidity_target} = delete($out{target}) // 'NONE';
        $out{dataset_date} = _dataset_date($file);
        $out{source_file} = basename($file);

        _add_existing_pip_distances(\%out, $self->{pip_size});
        _add_multitimeframe_features(\%out, $candles, $i, $self->{pip_size});
        _add_large_support_resistance(\%out, $candles, $i, $self->{pip_size});
        _add_supply_demand(\%out, $candles, $i, $self->{pip_size});

        my $targets = _future_trace_counts($candles, $i, [3,5,10,15]);
        $out{"target_trace_$_"} = $targets->{$_} for qw(3 5 10 15);
        push @rows, \%out;
    }

    my $features = Market::ML::FinalGhostFeatureSchema->select_feature_columns(rows => \@rows);
    return {
        rows => \@rows,
        feature_columns => $features,
        source_file => basename($file),
        candle_count => scalar(@$candles),
        ghost_count => scalar(@rows),
    };
}

sub _add_existing_pip_distances {
    my ($row, $pip) = @_;
    my $atr = _num($row->{atr_14});
    for my $pair (
        ['distance_nearest_bsl_atr','distance_nearest_bsl_pips'],
        ['distance_nearest_ssl_atr','distance_nearest_ssl_pips'],
        ['distance_fvg_atr','distance_fvg_pips'],
        ['distance_ob_atr','distance_ob_pips'],
        ['distance_equal_level_atr','distance_equal_level_pips'],
        ['distance_last_structure_event_atr','distance_last_structure_event_pips'],
    ) {
        my ($src,$dst) = @$pair;
        $row->{$dst} = ($atr > 0 && defined($row->{$src})) ? (_num($row->{$src}) * $atr / $pip) : 0;
    }
    $row->{atr_1m_pips} = $atr > 0 ? $atr / $pip : 0;
}

sub _add_multitimeframe_features {
    my ($row, $candles, $i, $pip) = @_;
    for my $tf (1, 10, 60) {
        my $f = _timeframe_context($candles, $i, $tf, $pip);
        $row->{"tf_${tf}_$_"} = $f->{$_} for keys %$f;
    }
}

sub _timeframe_context {
    my ($candles, $i, $tf, $pip) = @_;
    my $current = $candles->[$i];
    my $price = ($current->{high} + $current->{low}) / 2;
    my $history_minutes = max(20 * $tf, 60);
    my $start = max(0, $i - $history_minutes + 1);

    my ($hi,$lo,$vol,$pv) = (-9e99,9e99,0,0);
    for my $j ($start .. $i) {
        my $c = $candles->[$j];
        $hi = $c->{high} if $c->{high} > $hi;
        $lo = $c->{low} if $c->{low} < $lo;
        my $typ = ($c->{high} + $c->{low} + $c->{close}) / 3;
        $vol += $c->{volume};
        $pv += $typ * $c->{volume};
    }
    my $vwap = $vol > 0 ? $pv / $vol : $price;

    my @blocks;
    for my $b (0 .. 19) {
        my $end = $i - $b * $tf;
        last if $end < 0;
        my $bs = max(0, $end - $tf + 1);
        my ($bh,$bl,$bv) = (-9e99,9e99,0);
        for my $j ($bs .. $end) {
            my $c = $candles->[$j];
            $bh = $c->{high} if $c->{high} > $bh;
            $bl = $c->{low} if $c->{low} < $bl;
            $bv += $c->{volume};
        }
        push @blocks, { open=>$candles->[$bs]{open}, high=>$bh, low=>$bl, close=>$candles->[$end]{close}, volume=>$bv };
    }
    @blocks = reverse @blocks;

    my @trs;
    for my $k (0 .. $#blocks) {
        my $tr = $blocks[$k]{high} - $blocks[$k]{low};
        if ($k > 0) {
            my $pc = $blocks[$k-1]{close};
            $tr = max($tr, abs($blocks[$k]{high}-$pc), abs($blocks[$k]{low}-$pc));
        }
        push @trs, $tr;
    }
    my @atr_part = @trs > 14 ? @trs[$#trs-13 .. $#trs] : @trs;
    my $atr = @atr_part ? sum(@atr_part)/@atr_part : 0;

    my @vols = map { $_->{volume} } @blocks;
    my $ema = @vols ? $vols[0] : 0;
    my $alpha = 2/10;
    if (@vols > 1) {
        for my $vv (@vols[1 .. $#vols]) {
            $ema = $alpha * $vv + (1-$alpha) * $ema;
        }
    }
    my $curr_vol = @blocks ? $blocks[-1]{volume} : $current->{volume};

    my $range = $hi - $lo;
    my $fib382 = $lo + 0.382 * $range;
    my $fib500 = $lo + 0.500 * $range;
    my $fib618 = $lo + 0.618 * $range;

    my ($poc,$vah,$val) = _volume_profile($candles, $start, $i, 24, $price);
    my $trend = _trend_channel(\@blocks, $price, $pip, $atr);

    my $first_close = @blocks ? $blocks[0]{open} : $current->{open};
    return {
        atr_pips                 => $atr / $pip,
        range_pips               => $range / $pip,
        return_pips              => ($current->{close} - $first_close) / $pip,
        volume                   => $curr_vol,
        volume_ema9              => $ema,
        volume_ratio_ema9        => $ema > 0 ? $curr_vol/$ema : 1,
        vwap_distance_pips       => ($price - $vwap) / $pip,
        poc_distance_pips        => ($price - $poc) / $pip,
        vah_distance_pips        => ($price - $vah) / $pip,
        val_distance_pips        => ($price - $val) / $pip,
        fib382_distance_pips     => ($price - $fib382) / $pip,
        fib500_distance_pips     => ($price - $fib500) / $pip,
        fib618_distance_pips     => ($price - $fib618) / $pip,
        resistance_distance_pips => ($hi - $price) / $pip,
        support_distance_pips    => ($price - $lo) / $pip,
        trend_distance_pips      => $trend->{distance_pips},
        channel_halfwidth_pips   => $trend->{halfwidth_pips},
        channel_lower_touches    => $trend->{lower_touches},
        channel_upper_touches    => $trend->{upper_touches},
        channel_valid_3_touches  => $trend->{valid},
    };
}

sub _trend_channel {
    my ($blocks, $price, $pip, $atr) = @_;
    my $n = scalar(@$blocks);
    return {distance_pips=>0,halfwidth_pips=>0,lower_touches=>0,upper_touches=>0,valid=>0} if $n < 3;
    my ($sx,$sy,$sxx,$sxy)=(0,0,0,0);
    for my $i (0..$#$blocks) {
        my $y=$blocks->[$i]{close}; $sx+=$i; $sy+=$y; $sxx+=$i*$i; $sxy+=$i*$y;
    }
    my $den=$n*$sxx-$sx*$sx;
    my $slope=$den ? ($n*$sxy-$sx*$sy)/$den : 0;
    my $intercept=($sy-$slope*$sx)/$n;
    my @res;
    for my $i (0..$#$blocks) { push @res, $blocks->[$i]{close}-($intercept+$slope*$i); }
    my $mean=sum(@res)/@res;
    my $sd=sqrt(sum(map {($_-$mean)**2} @res)/@res);
    $sd = $atr*0.15 if $sd < $atr*0.15;
    my ($lt,$ut)=(0,0);
    my $tol=max($atr*0.30,$pip);
    for my $i (0..$#$blocks) {
        my $center=$intercept+$slope*$i;
        $lt++ if abs($blocks->[$i]{low}-($center-$sd)) <= $tol;
        $ut++ if abs($blocks->[$i]{high}-($center+$sd)) <= $tol;
    }
    my $center_now=$intercept+$slope*($n-1);
    return {
        distance_pips => ($price-$center_now)/$pip,
        halfwidth_pips => $sd/$pip,
        lower_touches=>$lt, upper_touches=>$ut,
        valid => (($lt>=3 || $ut>=3) && $n>=12) ? 1 : 0,
    };
}

sub _volume_profile {
    my ($candles,$start,$end,$bins,$fallback)=@_;
    my ($lo,$hi)=(9e99,-9e99);
    for my $j ($start..$end) { $lo=min($lo,$candles->[$j]{low}); $hi=max($hi,$candles->[$j]{high}); }
    return ($fallback,$fallback,$fallback) if $hi <= $lo;
    my @v=(0)x$bins; my $step=($hi-$lo)/$bins;
    for my $j ($start..$end) {
        my $c=$candles->[$j]; my $p=($c->{high}+$c->{low}+$c->{close})/3;
        my $b=int(($p-$lo)/$step); $b=0 if $b<0; $b=$bins-1 if $b>=$bins;
        $v[$b]+=$c->{volume};
    }
    my $poc_idx=0;
    for my $bi (1 .. $#v) {
        $poc_idx = $bi if $v[$bi] > $v[$poc_idx];
    }
    my $total=sum(@v)||1; my $acc=$v[$poc_idx]; my ($l,$r)=($poc_idx,$poc_idx);
    while ($acc/$total < 0.70 && ($l>0 || $r<$#v)) {
        my $lv=$l>0 ? $v[$l-1] : -1; my $rv=$r<$#v ? $v[$r+1] : -1;
        if ($rv >= $lv) { $r++; $acc += $v[$r]; } else { $l--; $acc += $v[$l]; }
    }
    my $center=sub { my($b)=@_; return $lo+($b+0.5)*$step; };
    return ($center->($poc_idx), $center->($r), $center->($l));
}

sub _add_large_support_resistance {
    my ($row,$candles,$i,$pip)=@_;
    my $price=($candles->[$i]{high}+$candles->[$i]{low})/2;
    for my $item ([240,'4h'],[1440,'daily'],[10080,'weekly']) {
        my ($minutes,$name)=@$item; my $start=max(0,$i-$minutes+1); my($hi,$lo)=(-9e99,9e99);
        for my $j ($start..$i) { $hi=max($hi,$candles->[$j]{high}); $lo=min($lo,$candles->[$j]{low}); }
        $row->{"sr_${name}_resistance_pips"}=($hi-$price)/$pip;
        $row->{"sr_${name}_support_pips"}=($price-$lo)/$pip;
    }
}

sub _add_supply_demand {
    my ($row,$candles,$i,$pip)=@_;
    my $start=max(1,$i-240); my($best_bull,$best_bear,$bull_score,$bear_score);
    for my $j ($start..$i) {
        my $c=$candles->[$j]; my $body=$c->{close}-$c->{open}; my $range=max($c->{high}-$c->{low},$pip);
        my $score=abs($body)/$range * $c->{volume};
        if ($body>0 && (!defined($bull_score)||$score>$bull_score)) { ($bull_score,$best_bull)=($score,$c); }
        if ($body<0 && (!defined($bear_score)||$score>$bear_score)) { ($bear_score,$best_bear)=($score,$c); }
    }
    my $price=($candles->[$i]{high}+$candles->[$i]{low})/2;
    my $demand=defined($best_bull)?$best_bull->{low}:$price;
    my $supply=defined($best_bear)?$best_bear->{high}:$price;
    $row->{demand_distance_pips}=($price-$demand)/$pip;
    $row->{supply_distance_pips}=($supply-$price)/$pip;
}

sub _future_trace_counts {
    my ($candles,$i,$horizons)=@_;
    my $upper=$candles->[$i]{high}; my $lower=$candles->[$i]{low}; my $count=0; my %out;
    my %wanted=map {$_=>1} @$horizons;
    my $maxh=max(@$horizons);
    for my $step (1..$maxh) {
        my $c=$candles->[$i+$step] or last;
        if ($c->{high} > $upper) { $count++; $upper=$c->{high}; }
        if ($c->{low} < $lower) { $count++; $lower=$c->{low}; }
        $out{$step}=$count if $wanted{$step};
    }
    $out{$_}//=$count for @$horizons;
    return \%out;
}

sub _load_candles {
    my ($file)=@_;
    open my $fh,'<:encoding(UTF-8)',$file or croak "No se puede abrir '$file': $!\n";
    <$fh>; my @c;
    while (my $line=<$fh>) {
        chomp $line; $line =~ s/\r$//; next if $line eq '';
        my @v=split /,/, $line; next if @v<6;
        push @c,{time=>$v[0],open=>0+$v[1],high=>0+$v[2],low=>0+$v[3],close=>0+$v[4],volume=>0+$v[5]};
    }
    close $fh; return \@c;
}

sub _dataset_date { my($f)=@_; my$n=basename($f); return "$1-$2" if $n=~/(\d{4})_(\d{2})/; return 'UNKNOWN'; }
sub _num { my($v)=@_; return 0 if !defined($v)||$v eq ''; return 0+$v; }

1;
