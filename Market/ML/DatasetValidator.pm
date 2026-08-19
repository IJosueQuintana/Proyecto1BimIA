package Market::ML::DatasetValidator;

use strict;
use warnings;

sub new {
    my ($class, %args) = @_;

    return bless {
        verbose => exists $args{verbose}
            ? $args{verbose}
            : 1,
    }, $class;
}

sub validate {
    my ($self, %args) = @_;

    my $rows =
        $args{rows}
        // [];

    die "rows debe ser una referencia ARRAY\n"
        if ref($rows) ne 'ARRAY';

    my %report = (
        total_rows                      => scalar(@$rows),
        valid_rows                      => 0,
        invalid_rows                    => 0,
        duplicate_rows                  => 0,
        confirmation_before_pivot       => 0,
        negative_confirmation_delay     => 0,
        atr_zero                        => 0,
        volume_zero                     => 0,
        invalid_pivot_side              => 0,
        unknown_structure               => 0,
        invalid_target                  => 0,
        missing_timestamp               => 0,
        missing_price                   => 0,
        missing_index                   => 0,
    );

    my %pivot_side_count;
    my %structure_count;
    my %target_count;
    my %timeframe_count;
    my %seen;

    my @errors;
    my @warnings;

    for my $position (0 .. $#$rows) {

        my $row =
            $rows->[$position];

        if (ref($row) ne 'HASH') {
            $report{invalid_rows}++;

            push @errors, {
                row     => $position + 1,
                message => 'La fila no es un HASH',
            };

            next;
        }

        my $row_valid = 1;

        my $pivot_index =
            $row->{pivot_index};

        my $confirmation_index =
            $row->{confirmation_index};

        my $pivot_side =
            uc(
                $row->{pivot_side}
                // 'UNKNOWN'
            );

        my $structure =
            uc(
                $row->{structure_type}
                // 'UNKNOWN'
            );

        my $target =
            uc(
                $row->{target}
                // 'NONE'
            );

        # ============================================================
        # ÍNDICES
        # ============================================================
        if (
            !defined $pivot_index
            ||
            $pivot_index !~ /^-?\d+$/
        ) {
            $report{missing_index}++;
            $row_valid = 0;

            push @errors, {
                row     => $position + 1,
                message => 'pivot_index ausente o inválido',
            };
        }

        if (
            !defined $confirmation_index
            ||
            $confirmation_index !~ /^-?\d+$/
        ) {
            $report{missing_index}++;
            $row_valid = 0;

            push @errors, {
                row     => $position + 1,
                message => 'confirmation_index ausente o inválido',
            };
        }

        if (
            defined $pivot_index
            &&
            defined $confirmation_index
            &&
            $pivot_index =~ /^-?\d+$/
            &&
            $confirmation_index =~ /^-?\d+$/
        ) {
            if ($confirmation_index < $pivot_index) {

                $report{confirmation_before_pivot}++;
                $row_valid = 0;

                push @errors, {
                    row     => $position + 1,
                    message =>
                        "confirmation_index=$confirmation_index "
                        . "< pivot_index=$pivot_index",
                };
            }

            my $delay =
                $confirmation_index
                -
                $pivot_index;

            if ($delay < 0) {
                $report{negative_confirmation_delay}++;
            }
        }

        # ============================================================
        # DUPLICADOS
        # ============================================================
        my $duplicate_key =
            join(
                '|',
                defined $row->{timeframe}
                    ? $row->{timeframe}
                    : '',
                defined $pivot_index
                    ? $pivot_index
                    : '',
                $pivot_side,
                defined $row->{pivot_price}
                    ? $row->{pivot_price}
                    : '',
            );

        if ($seen{$duplicate_key}++) {

            $report{duplicate_rows}++;

            push @warnings, {
                row     => $position + 1,
                message =>
                    "Posible pivote duplicado: $duplicate_key",
            };
        }

        # ============================================================
        # TIPO DEL PIVOTE
        # ============================================================
        $pivot_side_count{$pivot_side}++;

        if (
            $pivot_side ne 'HIGH'
            &&
            $pivot_side ne 'LOW'
        ) {
            $report{invalid_pivot_side}++;
            $row_valid = 0;

            push @errors, {
                row     => $position + 1,
                message =>
                    "pivot_side inválido: $pivot_side",
            };
        }

        # ============================================================
        # ESTRUCTURA
        # ============================================================
        $structure_count{$structure}++;

        if (
            $structure eq 'UNKNOWN'
            ||
            $structure eq ''
        ) {
            $report{unknown_structure}++;

            push @warnings, {
                row     => $position + 1,
                message => 'structure_type desconocido',
            };
        }

        # ============================================================
        # TARGET
        # ============================================================
        $target_count{$target}++;

        if (
            $target ne 'RUN'
            &&
            $target ne 'GRAB'
            &&
            $target ne 'SWEEP'
            &&
            $target ne 'NONE'
        ) {
            $report{invalid_target}++;
            $row_valid = 0;

            push @errors, {
                row     => $position + 1,
                message =>
                    "target inválido: $target",
            };
        }

        # ============================================================
        # PRECIO
        # ============================================================
        if (
            !defined $row->{pivot_price}
            ||
            $row->{pivot_price} eq ''
        ) {
            $report{missing_price}++;
            $row_valid = 0;

            push @errors, {
                row     => $position + 1,
                message => 'pivot_price ausente',
            };
        }

        # ============================================================
        # FECHAS
        # ============================================================
        if (
            !defined $row->{pivot_timestamp}
            ||
            $row->{pivot_timestamp} eq ''
        ) {
            $report{missing_timestamp}++;

            push @warnings, {
                row     => $position + 1,
                message => 'pivot_timestamp ausente',
            };
        }

        # ============================================================
        # ATR
        # ============================================================
        my $atr =
            _num($row->{atr_14});

        if ($atr <= 0) {
            $report{atr_zero}++;

            push @warnings, {
                row     => $position + 1,
                message => 'ATR igual o menor que cero',
            };
        }

        # ============================================================
        # VOLUMEN
        # ============================================================
        my $volume =
            _num($row->{pivot_volume});

        if ($volume <= 0) {
            $report{volume_zero}++;

            push @warnings, {
                row     => $position + 1,
                message => 'Volumen igual o menor que cero',
            };
        }

        # ============================================================
        # TIMEFRAME
        # ============================================================
        my $timeframe =
            defined $row->{timeframe}
            ? $row->{timeframe}
            : 'UNKNOWN';

        $timeframe_count{$timeframe}++;

        if ($row_valid) {
            $report{valid_rows}++;
        }
        else {
            $report{invalid_rows}++;
        }
    }

    $report{pivot_side_count} =
        \%pivot_side_count;

    $report{structure_count} =
        \%structure_count;

    $report{target_count} =
        \%target_count;

    $report{timeframe_count} =
        \%timeframe_count;

    $report{errors} =
        \@errors;

    $report{warnings} =
        \@warnings;

    return \%report;
}

sub print_report {
    my ($self, $report) = @_;

    die "report debe ser HASH\n"
        if ref($report) ne 'HASH';

    print "\n";
    print "========================================\n";
    print "       VALIDACIÓN DEL DATASET ML\n";
    print "========================================\n";

    print "Filas totales:                 "
        . ($report->{total_rows} // 0)
        . "\n";

    print "Filas válidas:                 "
        . ($report->{valid_rows} // 0)
        . "\n";

    print "Filas inválidas:               "
        . ($report->{invalid_rows} // 0)
        . "\n";

    print "Duplicados posibles:           "
        . ($report->{duplicate_rows} // 0)
        . "\n";

    print "Confirmación antes del pivote: "
        . ($report->{confirmation_before_pivot} // 0)
        . "\n";

    print "ATR igual a cero:              "
        . ($report->{atr_zero} // 0)
        . "\n";

    print "Volumen igual a cero:          "
        . ($report->{volume_zero} // 0)
        . "\n";

    print "Pivot side inválido:           "
        . ($report->{invalid_pivot_side} // 0)
        . "\n";

    print "Estructura desconocida:        "
        . ($report->{unknown_structure} // 0)
        . "\n";

    print "Target inválido:               "
        . ($report->{invalid_target} // 0)
        . "\n";

    print "Timestamp ausente:             "
        . ($report->{missing_timestamp} // 0)
        . "\n";

    print "\nPIVOT SIDE:\n";
    _print_counts(
        $report->{pivot_side_count}
    );

    print "\nESTRUCTURA:\n";
    _print_counts(
        $report->{structure_count}
    );

    print "\nTARGET:\n";
    _print_counts(
        $report->{target_count}
    );

    print "\nTIMEFRAME:\n";
    _print_counts(
        $report->{timeframe_count}
    );

    if (
        $self->{verbose}
        &&
        @{$report->{errors} // []}
    ) {
        print "\nPRIMEROS ERRORES:\n";

        my $limit =
            @{$report->{errors}} < 10
            ? scalar @{$report->{errors}}
            : 10;

        for my $i (0 .. $limit - 1) {

            my $error =
                $report->{errors}[$i];

            print "  Fila $error->{row}: "
                . "$error->{message}\n";
        }
    }

    if (
        $self->{verbose}
        &&
        @{$report->{warnings} // []}
    ) {
        print "\nPRIMERAS ADVERTENCIAS:\n";

        my $limit =
            @{$report->{warnings}} < 10
            ? scalar @{$report->{warnings}}
            : 10;

        for my $i (0 .. $limit - 1) {

            my $warning =
                $report->{warnings}[$i];

            print "  Fila $warning->{row}: "
                . "$warning->{message}\n";
        }
    }

    print "========================================\n\n";

    return;
}

sub _print_counts {
    my ($counts) = @_;

    return
        if ref($counts) ne 'HASH';

    for my $key (sort keys %$counts) {
        print "  $key => $counts->{$key}\n";
    }
}

sub _num {
    my ($value) = @_;

    return 0
        if !defined $value;

    return 0 + $value;
}

1;