package Market::ML::HMMStateCalibrator;

use strict;
use warnings;
use Carp qw(croak);
use Market::ML::ClassificationMetrics;

sub new {
    my ($class, %args) = @_;
    return bless {
        expansion_threshold => defined($args{expansion_threshold}) ? 0 + $args{expansion_threshold} : 0.50,
        require_interaction  => $args{require_interaction} ? 1 : 0,
        fitted               => $args{fitted} ? 1 : 0,
        validation_summary   => $args{validation_summary},
    }, $class;
}

sub fit {
    my ($self, %args) = @_;
    my $actual       = $args{actual}       // [];
    my $posteriors   = $args{posteriors}   // [];
    my $sequence_ids = $args{sequence_ids} // [];
    my $thresholds   = $args{thresholds}   // [map { $_ / 100 } (50, 55, 60, 65, 70, 75, 80, 85, 90, 92, 94, 95, 96, 97, 98, 99)];
    my $guards       = $args{guards}       // [0, 1];

    _validate_inputs($actual, $posteriors, $sequence_ids);
    croak "thresholds debe ser ARRAY\n" if ref($thresholds) ne 'ARRAY' || !@$thresholds;
    croak "guards debe ser ARRAY\n" if ref($guards) ne 'ARRAY' || !@$guards;

    my @labels = qw(IDLE APPROACH INTERACTION EXPANSION);
    my $metrics = Market::ML::ClassificationMetrics->new(labels => \@labels);
    my ($best, @trials);

    for my $guard (@$guards) {
        for my $threshold (@$thresholds) {
            next if $threshold < 0 || $threshold > 1;
            my $pred = _apply_config(
                posteriors          => $posteriors,
                sequence_ids        => $sequence_ids,
                expansion_threshold => $threshold,
                require_interaction => $guard ? 1 : 0,
            );
            my $report = $metrics->evaluate(actual => $actual, predicted => $pred);
            my $exp = $report->{per_class}{EXPANSION};
            my $trial = {
                expansion_threshold => 0 + $threshold,
                require_interaction  => $guard ? 1 : 0,
                macro_f1             => $report->{macro_f1},
                accuracy             => $report->{accuracy},
                expansion_precision  => $exp->{precision},
                expansion_recall     => $exp->{recall},
                expansion_f1         => $exp->{f1},
                report               => $report,
            };
            push @trials, $trial;

            if (!_is_better($best, $trial)) {
                next;
            }
            $best = $trial;
        }
    }

    croak "No se pudo seleccionar una calibración\n" if !$best;
    $self->{expansion_threshold} = $best->{expansion_threshold};
    $self->{require_interaction}  = $best->{require_interaction};
    $self->{validation_summary} = {
        macro_f1            => $best->{macro_f1},
        accuracy            => $best->{accuracy},
        expansion_precision => $best->{expansion_precision},
        expansion_recall    => $best->{expansion_recall},
        expansion_f1        => $best->{expansion_f1},
        trials              => scalar(@trials),
    };
    $self->{fitted} = 1;
    return { best => $best, trials => \@trials };
}

sub apply {
    my ($self, %args) = @_;
    croak "HMMStateCalibrator todavía no fue ajustado\n" if !$self->{fitted};
    my $posteriors   = $args{posteriors}   // [];
    my $sequence_ids = $args{sequence_ids} // [];
    croak "posteriors debe ser ARRAY\n" if ref($posteriors) ne 'ARRAY';
    croak "sequence_ids debe ser ARRAY y coincidir con posteriors\n"
        if ref($sequence_ids) ne 'ARRAY' || @$sequence_ids != @$posteriors;

    return _apply_config(
        posteriors          => $posteriors,
        sequence_ids        => $sequence_ids,
        expansion_threshold => $self->{expansion_threshold},
        require_interaction => $self->{require_interaction},
    );
}

sub config {
    my ($self) = @_;
    return {
        expansion_threshold => $self->{expansion_threshold},
        require_interaction  => $self->{require_interaction},
        fitted               => $self->{fitted},
        validation_summary   => $self->{validation_summary},
    };
}

sub _apply_config {
    my (%args) = @_;
    my $posteriors   = $args{posteriors};
    my $sequence_ids = $args{sequence_ids};
    my $threshold    = $args{expansion_threshold};
    my $guard        = $args{require_interaction};
    my @states = qw(IDLE APPROACH INTERACTION EXPANSION);
    my (@predicted, $previous_sequence, $previous_state);

    for my $i (0 .. $#$posteriors) {
        my $posterior = $posteriors->[$i];
        croak "Posterior inválido en posición $i\n" if ref($posterior) ne 'HASH';
        my $sequence = defined($sequence_ids->[$i]) ? "$sequence_ids->[$i]" : '';
        if (!defined($previous_sequence) || $sequence ne $previous_sequence) {
            $previous_state = undef;
        }

        my @ordered = sort {
            ($posterior->{$b} // 0) <=> ($posterior->{$a} // 0)
                || _state_index($a) <=> _state_index($b)
        } @states;
        my $best = $ordered[0];

        if ($best eq 'EXPANSION') {
            my $prob_ok = ($posterior->{EXPANSION} // 0) >= $threshold;
            my $transition_ok = !$guard || (defined($previous_state) && $previous_state eq 'INTERACTION');
            if (!$prob_ok || !$transition_ok) {
                ($best) = grep { $_ ne 'EXPANSION' } @ordered;
                $best //= 'IDLE';
            }
        }

        push @predicted, $best;
        $previous_sequence = $sequence;
        $previous_state = $best;
    }
    return \@predicted;
}

sub _is_better {
    my ($best, $trial) = @_;
    return 1 if !$best;
    return 1 if $trial->{macro_f1} > $best->{macro_f1} + 1e-12;
    return 0 if $trial->{macro_f1} < $best->{macro_f1} - 1e-12;
    return 1 if $trial->{expansion_f1} > $best->{expansion_f1} + 1e-12;
    return 0 if $trial->{expansion_f1} < $best->{expansion_f1} - 1e-12;
    return 1 if $trial->{accuracy} > $best->{accuracy} + 1e-12;
    return 0;
}

sub _validate_inputs {
    my ($actual, $posteriors, $sequence_ids) = @_;
    croak "actual debe ser ARRAY\n" if ref($actual) ne 'ARRAY';
    croak "posteriors debe ser ARRAY\n" if ref($posteriors) ne 'ARRAY';
    croak "sequence_ids debe ser ARRAY\n" if ref($sequence_ids) ne 'ARRAY';
    croak "actual, posteriors y sequence_ids deben tener igual longitud\n"
        if @$actual != @$posteriors || @$actual != @$sequence_ids;
}

sub _state_index {
    my ($state) = @_;
    my %index = (IDLE => 0, APPROACH => 1, INTERACTION => 2, EXPANSION => 3);
    return $index{$state} // 999;
}

1;
