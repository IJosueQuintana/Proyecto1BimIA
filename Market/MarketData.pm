package Market::MarketData;
use strict;
use warnings;
use Time::Piece;

sub new {
    my ($class) = @_;
    my $self = { data => { 1 => [] }, timeframe => 1 };
    bless $self, $class;
    return $self;
}

sub get_data { return $_[0]->{data}; }

sub add_candle {
    my ($self, $candle) = @_;
    push @{$self->{data}{1}}, $candle;
}

sub load_csv {
    my ($self, $file) = @_;
    open my $fh, '<', $file or die "No se puede abrir $file: $!";
    my $header = <$fh>;
    while (my $line = <$fh>) {
        chomp $line;
        next if $line =~ /^\s*$/;
        my ($time, $open, $high, $low, $close, $volume) = split /,/, $line;
        $time =~ s/\.\d+//;
        my $epoch = _to_epoch($time);
        $self->add_candle({
            time => $time, epoch => $epoch,
            open => $open + 0, high => $high + 0, low => $low + 0,
            close => $close + 0, volume => $volume + 0,
        });
    }
    close $fh;
    $self->build_timeframes();
}

sub _to_epoch {
    my ($time) = @_;
    my $clean = $time;
    $clean =~ s/[-+]\d\d:\d\d$//;       # quitamos zona horaria para hacerlo simple
    my $t = Time::Piece->strptime($clean, '%Y-%m-%dT%H:%M:%S');
    return $t->epoch;
}

sub _bucket_epoch {
    my ($epoch, $tf) = @_;

    if ($tf eq 'D') {
        my $t = localtime($epoch);
        my $date = $t->ymd;
        return Time::Piece->strptime($date . 'T00:00:00', '%Y-%m-%dT%H:%M:%S')->epoch;
    }

    if ($tf eq 'W') {
        my $t = localtime($epoch);
        my $date = $t->ymd;
        my $midnight = Time::Piece->strptime($date . 'T00:00:00', '%Y-%m-%dT%H:%M:%S')->epoch;

        my $dow = $t->strftime('%u'); # 1 lunes ... 7 domingo
        return $midnight - (($dow - 1) * 86400);
    }

    my $seconds = $tf * 60;
    return int($epoch / $seconds) * $seconds;
}
sub build_tf_candles {
    my ($self, $tf) = @_;
    return $self->{data_1m} if "$tf" eq "1";

    my @out;
    my $current;
    my $bucket = -1;

    for my $c (@{$self->{data}{1}}) {
        my $b = _bucket_epoch($c->{epoch}, $tf);
        if (!defined $current || $b != $bucket) {
            push @out, $current if defined $current;
            $bucket = $b;
            $current = {
                time => $c->{time}, epoch => $b,
                open => $c->{open}, high => $c->{high}, low => $c->{low},
                close => $c->{close}, volume => $c->{volume},
            };
        } else {
            $current->{high} = $c->{high} if $c->{high} > $current->{high};
            $current->{low}  = $c->{low}  if $c->{low}  < $current->{low};
            $current->{close} = $c->{close};
            $current->{volume} += $c->{volume};
        }
    }
    push @out, $current if defined $current;
    $self->{data}{$tf} = \@out;
    return \@out;
}

sub build_timeframes {
    my ($self) = @_;

    for my $tf (5, 15, 60, 120, 240, 'D', 'W') {
        $self->build_tf_candles($tf);
    }
}

sub set_timeframe {
    my ($self, $tf) = @_;
    $self->{timeframe} = $tf;
    $self->build_tf_candles($tf) if !exists $self->{data}{$tf};
}

sub _active_array { return $_[0]->{data}{ $_[0]->{timeframe} }; }

sub get_slice {
    my ($self, $start, $end) = @_;
    my $a = $self->_active_array();
    $start = 0 if $start < 0;
    $end = $#$a if $end > $#$a;
    return [] if $end < $start;
    return [ @$a[$start .. $end] ];
}

sub get_candle { return $_[0]->_active_array()->[$_[1]]; }
sub size       { return scalar @{$_[0]->_active_array()}; }
sub last_index { return $_[0]->size() - 1; }
sub last_candle { return $_[0]->_active_array()->[-1]; }
sub get_timestamp { return $_[0]->get_candle($_[1])->{time}; }

sub merge_delta_row {
    my ($self, $row) = @_;
    my $last = $self->last_candle();
    if (defined $last && $last->{time} eq $row->{time}) { %$last = (%$last, %$row); }
    else { $self->add_candle($row); }
    $self->build_timeframes();
}

sub compute_time_anchors {
    my ($self) = @_;
    my $arr = $self->_active_array();
    my @anchors;
    my $prev_day = '';
    for my $i (0 .. $#$arr) {
        my $time = $arr->[$i]{time};
        my ($date, $hh, $mm) = $time =~ /(\d{4}-\d{2}-\d{2})T(\d{2}):(\d{2})/;
        next if !defined $date;
        if ($date ne $prev_day || $mm =~ /^(00|15|30|45)$/) {
            push @anchors, { index => $i, date => $date, hour => "$hh:$mm", new_day => ($date ne $prev_day) };
            $prev_day = $date;
        }
    }
    return \@anchors;
}

1;
