package Market::ML::HiddenMarkovModel;

use strict;
use warnings;
use List::Util qw(sum max);

sub new {
    my ($class, %args) = @_;
    my $states = $args{states} // [qw(RUN GRAB SWEEP)];
    die "states debe ser ARRAY y no puede estar vacío\n"
        if ref($states) ne 'ARRAY' || !@$states;

    return bless {
        states          => [@$states],
        smoothing       => defined($args{smoothing}) ? 0 + $args{smoothing} : 1.0,
        variance_floor  => defined($args{variance_floor}) ? 0 + $args{variance_floor} : 1e-2,
        initial         => {},
        transition      => {},
        means           => {},
        variances       => {},
        dimensions      => 0,
        fitted          => 0,
        train_log_likelihood => undef,
    }, $class;
}

sub fit {
    my ($self, %args) = @_;
    my $vectors = $args{vectors} // [];
    my $labels  = $args{labels} // [];
    my $sequence_ids = $args{sequence_ids};

    die "vectors debe ser ARRAY\n" if ref($vectors) ne 'ARRAY';
    die "labels debe ser ARRAY\n" if ref($labels) ne 'ARRAY';
    die "No se puede ajustar HMM con cero observaciones\n" if !@$vectors;
    die "Cantidad distinta de vectores y etiquetas\n" if @$vectors != @$labels;

    $sequence_ids = [ map { 'SEQUENCE_0' } @$vectors ]
        if ref($sequence_ids) ne 'ARRAY';
    die "Cantidad distinta de vectores y sequence_ids\n"
        if @$vectors != @$sequence_ids;

    my $d = @{$vectors->[0] // []};
    die "Los vectores no pueden estar vacíos\n" if !$d;
    for my $vector (@$vectors) {
        die "Todos los vectores deben tener la misma dimensión\n"
            if ref($vector) ne 'ARRAY' || @$vector != $d;
    }

    my @states = @{$self->{states}};
    my %valid = map { $_ => 1 } @states;
    my $alpha = $self->{smoothing};
    $alpha = 0 if $alpha < 0;

    my (%initial_counts, %transition_counts, %state_counts);
    my (%sums, %sum_squares);

    for my $state (@states) {
        $initial_counts{$state} = $alpha;
        for my $next (@states) {
            $transition_counts{$state}{$next} = $alpha;
        }
        $state_counts{$state} = 0;
        $sums{$state} = [(0) x $d];
        $sum_squares{$state} = [(0) x $d];
    }

    my $previous_sequence;
    my $previous_state;
    for my $i (0 .. $#$vectors) {
        my $state = uc($labels->[$i] // '');
        die "Estado desconocido '$state' en fila " . ($i + 1) . "\n"
            if !$valid{$state};
        my $sequence = defined($sequence_ids->[$i]) ? "$sequence_ids->[$i]" : '';

        if (!defined($previous_sequence) || $sequence ne $previous_sequence) {
            $initial_counts{$state}++;
        }
        else {
            $transition_counts{$previous_state}{$state}++;
        }

        $state_counts{$state}++;
        for my $j (0 .. $d - 1) {
            my $x = 0 + ($vectors->[$i][$j] // 0);
            $sums{$state}[$j] += $x;
            $sum_squares{$state}[$j] += $x * $x;
        }

        $previous_sequence = $sequence;
        $previous_state = $state;
    }

    my $initial_total = sum(values %initial_counts) || 1;
    my %initial = map { $_ => $initial_counts{$_} / $initial_total } @states;

    my %transition;
    for my $state (@states) {
        my $row_total = sum(values %{$transition_counts{$state}}) || 1;
        for my $next (@states) {
            $transition{$state}{$next} = $transition_counts{$state}{$next} / $row_total;
        }
    }

    my @global_mean = (0) x $d;
    for my $vector (@$vectors) {
        $global_mean[$_] += 0 + ($vector->[$_] // 0) for 0 .. $d - 1;
    }
    $_ /= @$vectors for @global_mean;

    my @global_var = (0) x $d;
    for my $vector (@$vectors) {
        for my $j (0 .. $d - 1) {
            my $delta = (0 + ($vector->[$j] // 0)) - $global_mean[$j];
            $global_var[$j] += $delta * $delta;
        }
    }
    $_ = $_ / @$vectors for @global_var;

    my (%means, %variances);
    for my $state (@states) {
        my $count = $state_counts{$state};
        my (@mean, @variance);
        for my $j (0 .. $d - 1) {
            my $m = $count ? $sums{$state}[$j] / $count : $global_mean[$j];
            my $v = $count
                ? ($sum_squares{$state}[$j] / $count) - ($m * $m)
                : $global_var[$j];
            $v = $self->{variance_floor} if !defined($v) || $v < $self->{variance_floor};
            push @mean, $m;
            push @variance, $v;
        }
        $means{$state} = \@mean;
        $variances{$state} = \@variance;
    }

    $self->{initial} = \%initial;
    $self->{transition} = \%transition;
    $self->{means} = \%means;
    $self->{variances} = \%variances;
    $self->{dimensions} = $d;
    $self->{state_counts} = \%state_counts;
    $self->{fitted} = 1;
    $self->{train_log_likelihood} = $self->score(
        vectors      => $vectors,
        sequence_ids => $sequence_ids,
    );
    return $self;
}

sub predict_online {
    my ($self, %args) = @_;
    _require_fitted($self);
    my $vectors = $args{vectors} // [];
    my $sequence_ids = $args{sequence_ids};
    $sequence_ids = [ map { 'SEQUENCE_0' } @$vectors ]
        if ref($sequence_ids) ne 'ARRAY';
    die "Cantidad distinta de vectores y sequence_ids\n"
        if @$vectors != @$sequence_ids;

    my @states = @{$self->{states}};
    my (@predicted, @posteriors);
    my ($previous_sequence, %log_alpha);

    for my $i (0 .. $#$vectors) {
        my $sequence = defined($sequence_ids->[$i]) ? "$sequence_ids->[$i]" : '';
        my %current;
        if (!defined($previous_sequence) || $sequence ne $previous_sequence) {
            for my $state (@states) {
                $current{$state} = _safe_log($self->{initial}{$state})
                    + $self->_log_emission($vectors->[$i], $state);
            }
        }
        else {
            for my $state (@states) {
                my @incoming = map {
                    $log_alpha{$_} + _safe_log($self->{transition}{$_}{$state})
                } @states;
                $current{$state} = _logsumexp(@incoming)
                    + $self->_log_emission($vectors->[$i], $state);
            }
        }

        my $normalizer = _logsumexp(values %current);
        my %posterior = map { $_ => exp($current{$_} - $normalizer) } @states;
        my ($best) = sort {
            $posterior{$b} <=> $posterior{$a}
                || _state_index($self, $a) <=> _state_index($self, $b)
        } @states;
        push @predicted, $best;
        push @posteriors, \%posterior;
        %log_alpha = %current;
        $previous_sequence = $sequence;
    }

    return wantarray ? (\@predicted, \@posteriors) : \@predicted;
}

sub viterbi {
    my ($self, %args) = @_;
    _require_fitted($self);
    my $vectors = $args{vectors} // [];
    my $sequence_ids = $args{sequence_ids};
    $sequence_ids = [ map { 'SEQUENCE_0' } @$vectors ]
        if ref($sequence_ids) ne 'ARRAY';
    die "Cantidad distinta de vectores y sequence_ids\n"
        if @$vectors != @$sequence_ids;

    my @output;
    my $start = 0;
    while ($start < @$vectors) {
        my $id = defined($sequence_ids->[$start]) ? "$sequence_ids->[$start]" : '';
        my $end = $start;
        $end++ while $end + 1 < @$vectors
            && (defined($sequence_ids->[$end + 1]) ? "$sequence_ids->[$end + 1]" : '') eq $id;
        my @slice = @$vectors[$start .. $end];
        push @output, @{$self->_viterbi_sequence(\@slice)};
        $start = $end + 1;
    }
    return \@output;
}

sub score {
    my ($self, %args) = @_;
    _require_fitted($self);
    my $vectors = $args{vectors} // [];
    my $sequence_ids = $args{sequence_ids};
    $sequence_ids = [ map { 'SEQUENCE_0' } @$vectors ]
        if ref($sequence_ids) ne 'ARRAY';
    die "Cantidad distinta de vectores y sequence_ids\n"
        if @$vectors != @$sequence_ids;

    my @states = @{$self->{states}};
    my ($previous_sequence, %log_alpha);
    my $total_log_likelihood = 0;

    for my $i (0 .. $#$vectors) {
        my $sequence = defined($sequence_ids->[$i]) ? "$sequence_ids->[$i]" : '';
        my %current;
        if (!defined($previous_sequence) || $sequence ne $previous_sequence) {
            if (defined $previous_sequence) {
                $total_log_likelihood += _logsumexp(values %log_alpha);
            }
            for my $state (@states) {
                $current{$state} = _safe_log($self->{initial}{$state})
                    + $self->_log_emission($vectors->[$i], $state);
            }
        }
        else {
            for my $state (@states) {
                my @incoming = map {
                    $log_alpha{$_} + _safe_log($self->{transition}{$_}{$state})
                } @states;
                $current{$state} = _logsumexp(@incoming)
                    + $self->_log_emission($vectors->[$i], $state);
            }
        }
        %log_alpha = %current;
        $previous_sequence = $sequence;
    }
    $total_log_likelihood += _logsumexp(values %log_alpha) if @$vectors;
    return $total_log_likelihood;
}

sub _viterbi_sequence {
    my ($self, $vectors) = @_;
    return [] if !@$vectors;
    my @states = @{$self->{states}};
    my (@delta, @psi);

    for my $state (@states) {
        $delta[0]{$state} = _safe_log($self->{initial}{$state})
            + $self->_log_emission($vectors->[0], $state);
        $psi[0]{$state} = undef;
    }

    for my $t (1 .. $#$vectors) {
        for my $state (@states) {
            my ($best_prev, $best_score);
            for my $prev (@states) {
                my $score = $delta[$t - 1]{$prev}
                    + _safe_log($self->{transition}{$prev}{$state});
                if (!defined($best_score) || $score > $best_score) {
                    $best_score = $score;
                    $best_prev = $prev;
                }
            }
            $delta[$t]{$state} = $best_score + $self->_log_emission($vectors->[$t], $state);
            $psi[$t]{$state} = $best_prev;
        }
    }

    my ($last) = sort {
        $delta[-1]{$b} <=> $delta[-1]{$a}
            || _state_index($self, $a) <=> _state_index($self, $b)
    } @states;
    my @path = ($last);
    for (my $t = $#$vectors; $t > 0; $t--) {
        unshift @path, $psi[$t]{$path[0]};
    }
    return \@path;
}

sub _log_emission {
    my ($self, $vector, $state) = @_;
    die "Vector con dimensión incorrecta\n"
        if ref($vector) ne 'ARRAY' || @$vector != $self->{dimensions};
    my $mean = $self->{means}{$state};
    my $variance = $self->{variances}{$state};
    my $log_prob = 0;
    my $log_two_pi = log(2 * 3.14159265358979323846);
    for my $j (0 .. $#$vector) {
        my $v = $variance->[$j];
        my $delta = (0 + ($vector->[$j] // 0)) - $mean->[$j];
        $log_prob += -0.5 * ($log_two_pi + log($v) + ($delta * $delta) / $v);
    }
    return $log_prob;
}

sub _logsumexp {
    my @values = @_;
    return -1e300 if !@values;
    my $maximum = max(@values);
    return $maximum if $maximum < -1e290;
    return $maximum + log(sum(map { exp($_ - $maximum) } @values));
}

sub _safe_log {
    my ($value) = @_;
    $value = 1e-300 if !defined($value) || $value <= 0;
    return log($value);
}

sub _state_index {
    my ($self, $target) = @_;
    for my $i (0 .. $#{$self->{states}}) {
        return $i if $self->{states}[$i] eq $target;
    }
    return 999;
}

sub _require_fitted {
    my ($self) = @_;
    die "HiddenMarkovModel todavía no fue ajustado\n" if !$self->{fitted};
}

sub states { return [@{$_[0]{states}}]; }
sub initial_probabilities { return { %{$_[0]{initial}} }; }
sub transition_matrix {
    my ($self) = @_;
    my %copy;
    for my $from (@{$self->{states}}) {
        $copy{$from} = { %{$self->{transition}{$from}} };
    }
    return \%copy;
}
sub means { return $_[0]{means}; }
sub variances { return $_[0]{variances}; }
sub dimensions { return $_[0]{dimensions}; }
sub smoothing { return $_[0]{smoothing}; }
sub train_log_likelihood { return $_[0]{train_log_likelihood}; }
sub state_counts { return { %{$_[0]{state_counts} // {}} }; }

1;
