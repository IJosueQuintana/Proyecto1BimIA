package Market::ML::CausalityAuditor;

use strict;
use warnings;
use Carp qw(croak);
use Scalar::Util qw(looks_like_number);

use Market::ML::FeatureSchema;

sub new {
    my ($class, %args) = @_;

    return bless {
        max_examples => $args{max_examples} // 20,
        strict       => exists $args{strict} ? $args{strict} : 1,
    }, $class;
}

sub audit_rows {
    my ($self, %args) = @_;

    my $rows = $args{rows} // [];
    my $name = $args{name} // 'dataset';
    my $declared_columns = $args{columns};

    croak "rows debe ser ARRAY\n" if ref($rows) ne 'ARRAY';
    croak "columns debe ser ARRAY cuando se especifica\n"
        if defined($declared_columns) && ref($declared_columns) ne 'ARRAY';

    my @errors;
    my @warnings;
    my %error_counts;
    my %warning_counts;

    my $add_issue = sub {
        my ($level, $code, $row_number, $message) = @_;
        my $target = $level eq 'error' ? \@errors : \@warnings;
        my $counts = $level eq 'error' ? \%error_counts : \%warning_counts;
        $counts->{$code}++;

        return if @$target >= $self->{max_examples};
        push @$target, {
            level      => $level,
            code       => $code,
            row_number => $row_number,
            message    => $message,
        };
    };

    my $feature_columns = Market::ML::FeatureSchema->select_feature_columns(
        rows => $rows,
    );

    # Esta validación es el cerrojo principal: ninguna columna que describa el
    # desenlace futuro puede entrar al vector X de los modelos.
    eval {
        Market::ML::FeatureSchema->validate_feature_columns(
            columns => $feature_columns,
        );
        1;
    } or do {
        my $message = $@ || 'Error desconocido al validar features';
        chomp $message;
        $add_issue->('error', 'FORBIDDEN_FEATURE', 0, $message);
    };

    if (defined $declared_columns && @$rows) {
        my %declared = map { $_ => 1 } @$declared_columns;
        my %present  = map { $_ => 1 } keys %{$rows->[0]};

        for my $column (sort keys %present) {
            next if $declared{$column};
            $add_issue->(
                'warning', 'UNDECLARED_COLUMN', 0,
                "La columna '$column' está presente pero no fue declarada para exportación"
            );
        }
        for my $column (@$declared_columns) {
            next if $present{$column};
            $add_issue->(
                'warning', 'MISSING_DECLARED_COLUMN', 0,
                "La columna declarada '$column' no aparece en la primera fila"
            );
        }
    }

    my %seen_identity;

    for my $i (0 .. $#$rows) {
        my $row = $rows->[$i];
        my $row_number = $i + 1;

        if (ref($row) ne 'HASH') {
            $add_issue->('error', 'ROW_NOT_HASH', $row_number, 'La fila no es HASH');
            next;
        }

        my $pivot = _number_or_undef($row->{pivot_index});
        my $confirm = _number_or_undef($row->{confirmation_index});
        my $delay = _number_or_undef($row->{confirmation_delay});

        if (!defined $pivot) {
            $add_issue->('error', 'MISSING_PIVOT_INDEX', $row_number,
                'pivot_index no es numérico');
        }
        if (!defined $confirm) {
            $add_issue->('error', 'MISSING_CONFIRMATION_INDEX', $row_number,
                'confirmation_index no es numérico');
        }

        if (defined($pivot) && defined($confirm)) {
            if ($confirm < $pivot) {
                $add_issue->('error', 'CONFIRMATION_BEFORE_PIVOT', $row_number,
                    "confirmation_index=$confirm es menor que pivot_index=$pivot");
            }

            my $expected_delay = $confirm - $pivot;
            if (defined($delay) && abs($delay - $expected_delay) > 1e-9) {
                $add_issue->('error', 'INVALID_CONFIRMATION_DELAY', $row_number,
                    "confirmation_delay=$delay pero debería ser $expected_delay");
            }

            _check_nonnegative_feature(
                $add_issue, $row, $row_number, 'bars_previous_pivot'
            );
            _check_nonnegative_feature(
                $add_issue, $row, $row_number, 'bars_since_structure_event'
            );
            _check_nonnegative_feature(
                $add_issue, $row, $row_number, 'bars_since_equal_level'
            );
            _check_nonnegative_feature(
                $add_issue, $row, $row_number, 'bars_since_fvg'
            );
            _check_nonnegative_feature(
                $add_issue, $row, $row_number, 'bars_since_ob'
            );
        }

        _check_timestamp_order($add_issue, $row, $row_number);
        _check_future_label_indices($add_issue, $row, $row_number, $confirm);
        _check_binary_columns($add_issue, $row, $row_number);
        _check_counts($add_issue, $row, $row_number);

        my $identity = join('|', map { defined($_) ? $_ : '' } (
            $row->{source_file}, $row->{symbol}, $row->{timeframe},
            $row->{pivot_index}, $row->{confirmation_index}
        ));
        if ($identity ne '||||') {
            if ($seen_identity{$identity}++) {
                $add_issue->('warning', 'DUPLICATE_CAUSAL_ROW', $row_number,
                    "Fila causal duplicada: $identity");
            }
        }
    }

    return {
        name             => $name,
        row_count        => scalar(@$rows),
        feature_count    => scalar(@$feature_columns),
        feature_columns  => $feature_columns,
        error_count      => _sum_counts(\%error_counts),
        warning_count    => _sum_counts(\%warning_counts),
        error_counts     => \%error_counts,
        warning_counts   => \%warning_counts,
        errors           => \@errors,
        warnings         => \@warnings,
        valid            => _sum_counts(\%error_counts) == 0 ? 1 : 0,
    };
}

sub assert_causal {
    my ($self, %args) = @_;
    my $report = $self->audit_rows(%args);

    if (!$report->{valid}) {
        die "Auditoría causal fallida para '$report->{name}': "
            . "$report->{error_count} error(es).\n";
    }

    return $report;
}

sub print_report {
    my ($self, $report) = @_;
    croak "report debe ser HASH\n" if ref($report) ne 'HASH';

    print "\n========================================\n";
    print " AUDITORÍA DE CAUSALIDAD: " . uc($report->{name} // 'DATASET') . "\n";
    print "========================================\n";
    print "Filas revisadas:        " . ($report->{row_count} // 0) . "\n";
    print "Features permitidas:    " . ($report->{feature_count} // 0) . "\n";
    print "Errores bloqueantes:     " . ($report->{error_count} // 0) . "\n";
    print "Advertencias:            " . ($report->{warning_count} // 0) . "\n";
    print "Resultado:               " . ($report->{valid} ? 'CAUSALMENTE VÁLIDO' : 'RECHAZADO') . "\n";

    if (@{$report->{errors} // []}) {
        print "\nPrimeros errores:\n";
        for my $issue (@{$report->{errors}}) {
            print "  [$issue->{code}] fila $issue->{row_number}: $issue->{message}\n";
        }
    }

    if (@{$report->{warnings} // []}) {
        print "\nPrimeras advertencias:\n";
        for my $issue (@{$report->{warnings}}) {
            print "  [$issue->{code}] fila $issue->{row_number}: $issue->{message}\n";
        }
    }

    print "========================================\n";
    return 1;
}

sub _check_nonnegative_feature {
    my ($add_issue, $row, $row_number, $column) = @_;
    return if !exists $row->{$column} || !defined($row->{$column}) || $row->{$column} eq '';

    my $value = _number_or_undef($row->{$column});
    if (!defined $value) {
        $add_issue->('error', 'NON_NUMERIC_BARS_SINCE', $row_number,
            "$column no es numérico");
        return;
    }

    # En PivotFeatureExtractor.pm, -1 es un valor centinela causal:
    # significa que todavía no existe un evento previo de ese tipo.
    # No representa un evento futuro ni debe bloquear el entrenamiento.
    return if $value == -1;

    if ($value < -1) {
        $add_issue->('error', 'INVALID_BARS_SINCE_SENTINEL', $row_number,
            "$column=$value es inválido; solo se permite -1 como centinela o valores >= 0");
    }
}

sub _check_timestamp_order {
    my ($add_issue, $row, $row_number) = @_;
    my $pivot_ts = $row->{pivot_timestamp};
    my $confirm_ts = $row->{confirmation_timestamp};
    return if !defined($pivot_ts) || !defined($confirm_ts)
        || $pivot_ts eq '' || $confirm_ts eq '';

    # Los timestamps ISO-8601 del proyecto tienen el mismo huso horario, por lo
    # que su orden lexicográfico coincide con el orden cronológico.
    if ($confirm_ts lt $pivot_ts) {
        $add_issue->('error', 'CONFIRMATION_TIMESTAMP_BEFORE_PIVOT', $row_number,
            "confirmation_timestamp=$confirm_ts precede a pivot_timestamp=$pivot_ts");
    }
}

sub _check_future_label_indices {
    my ($add_issue, $row, $row_number, $confirm) = @_;
    return if !defined $confirm;

    for my $column (qw(swept_index resolved_index)) {
        next if !exists $row->{$column} || !defined($row->{$column}) || $row->{$column} eq '';
        my $value = _number_or_undef($row->{$column});
        if (!defined $value) {
            $add_issue->('error', 'INVALID_FUTURE_LABEL_INDEX', $row_number,
                "$column no es numérico");
            next;
        }
        if ($value < $confirm) {
            $add_issue->('warning', 'LABEL_EVENT_BEFORE_CONFIRMATION', $row_number,
                "$column=$value ocurre antes de confirmation_index=$confirm; revisar etiquetado");
        }
    }

    my $swept = _number_or_undef($row->{swept_index});
    my $resolved = _number_or_undef($row->{resolved_index});
    if (defined($swept) && defined($resolved) && $resolved < $swept) {
        $add_issue->('error', 'RESOLUTION_BEFORE_SWEEP', $row_number,
            "resolved_index=$resolved es menor que swept_index=$swept");
    }
}

sub _check_binary_columns {
    my ($add_issue, $row, $row_number) = @_;
    for my $column (qw(
        near_equal_level inside_fvg fvg_mitigated
        inside_order_block ob_invalidated
    )) {
        next if !exists $row->{$column} || !defined($row->{$column}) || $row->{$column} eq '';
        my $value = $row->{$column};
        next if $value eq '0' || $value eq '1' || $value == 0 || $value == 1;
        $add_issue->('warning', 'NON_BINARY_FLAG', $row_number,
            "$column='$value' debería ser 0 o 1");
    }
}

sub _check_counts {
    my ($add_issue, $row, $row_number) = @_;
    for my $column (qw(
        bos_count_previous_20 choch_count_previous_20 active_fvg_count_50
        active_ob_count_50 bsl_count_previous_100 ssl_count_previous_100
        active_bsl_count active_ssl_count equal_levels_previous_100
    )) {
        next if !exists $row->{$column} || !defined($row->{$column}) || $row->{$column} eq '';
        my $value = _number_or_undef($row->{$column});
        if (!defined $value || $value < 0) {
            $add_issue->('error', 'INVALID_CAUSAL_COUNT', $row_number,
                "$column debe ser un conteo no negativo");
        }
    }
}

sub _number_or_undef {
    my ($value) = @_;
    return undef if !defined($value) || $value eq '' || !looks_like_number($value);
    return $value + 0;
}

sub _sum_counts {
    my ($counts) = @_;
    my $sum = 0;
    $sum += $_ for values %$counts;
    return $sum;
}

1;
