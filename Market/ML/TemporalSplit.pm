package Market::ML::TemporalSplit;

use strict;
use warnings;

sub new {
    my ($class, %args) = @_;
    return bless {}, $class;
}

sub sort_rows {
    my ($self, $rows) = @_;
    die "rows debe ser ARRAY\n" if ref($rows) ne 'ARRAY';

    my @sorted = sort {
        _row_key($a) cmp _row_key($b)
        || (($a->{confirmation_index} // 0) <=> ($b->{confirmation_index} // 0))
    } grep { ref($_) eq 'HASH' } @$rows;

    return \@sorted;
}

sub validate_ordered_groups {
    my ($self, %args) = @_;
    my $train      = $args{train_rows}      // [];
    my $validation = $args{validation_rows} // [];
    my $test       = $args{test_rows}       // [];

    for my $pair (
        [train => $train],
        [validation => $validation],
        [test => $test],
    ) {
        die "$pair->[0]_rows debe ser ARRAY\n" if ref($pair->[1]) ne 'ARRAY';
    }

    my $train_sorted = $self->sort_rows($train);
    my $validation_sorted = $self->sort_rows($validation);
    my $test_sorted = $self->sort_rows($test);

    my @errors;
    _check_internal_order('TRAIN', $train_sorted, \@errors);
    _check_internal_order('VALIDATION', $validation_sorted, \@errors);
    _check_internal_order('TEST', $test_sorted, \@errors);

    _check_boundary('TRAIN', $train_sorted, 'VALIDATION', $validation_sorted, \@errors);
    _check_boundary('VALIDATION', $validation_sorted, 'TEST', $test_sorted, \@errors);

    return {
        valid  => @errors ? 0 : 1,
        errors => \@errors,
        ranges => {
            train      => _range($train_sorted),
            validation => _range($validation_sorted),
            test       => _range($test_sorted),
        },
    };
}

sub build_walk_forward_folds {
    my ($self, %args) = @_;
    my $groups = $args{groups} // [];
    die "groups debe ser ARRAY\n" if ref($groups) ne 'ARRAY';
    die "Se requieren al menos dos grupos para walk-forward\n" if @$groups < 2;

    my @folds;
    my @accumulated;

    for my $i (0 .. $#$groups) {
        my $group = $groups->[$i];
        die "Cada grupo debe ser HASH\n" if ref($group) ne 'HASH';
        my $rows = $group->{rows} // [];
        die "rows del grupo debe ser ARRAY\n" if ref($rows) ne 'ARRAY';

        if ($i > 0) {
            push @folds, {
                fold             => $i,
                train_group_names => [ map { $_->{name} } @{$groups}[0 .. $i - 1] ],
                evaluation_group  => $group->{name},
                train_rows        => $self->sort_rows(\@accumulated),
                evaluation_rows   => $self->sort_rows($rows),
            };
        }

        push @accumulated, @$rows;
    }

    return \@folds;
}

sub latest_timestamp {
    my ($self, $rows) = @_;
    my $sorted = $self->sort_rows($rows // []);
    return undef if !@$sorted;
    return _row_key($sorted->[-1]);
}

sub filter_after_timestamp {
    my ($self, %args) = @_;
    my $rows = $args{rows} // [];
    my $after = $args{after};
    die "rows debe ser ARRAY\n" if ref($rows) ne 'ARRAY';
    return $self->sort_rows($rows) if !defined $after || $after eq '';
    my @filtered = grep {
        my $key = _row_key($_);
        $key ne '' && $key gt $after;
    } @$rows;
    return $self->sort_rows(\@filtered);
}

sub print_validation_report {
    my ($self, $report) = @_;
    print "\n========================================\n";
    print " VALIDACIÓN DEL ORDEN TEMPORAL\n";
    print "========================================\n";

    for my $name (qw(train validation test)) {
        my $range = $report->{ranges}{$name};
        printf "%-12s inicio=%s  fin=%s  filas=%d\n",
            uc($name),
            $range->{first} // 'N/A',
            $range->{last} // 'N/A',
            $range->{count} // 0;
    }

    if ($report->{valid}) {
        print "Resultado: CORRECTO. No existe mezcla temporal entre splits.\n";
    } else {
        print "Resultado: INCORRECTO.\n";
        print "  - $_\n" for @{$report->{errors}};
    }
    print "========================================\n";
}

sub _check_internal_order {
    my ($name, $rows, $errors) = @_;
    for my $i (1 .. $#$rows) {
        if (_row_key($rows->[$i]) lt _row_key($rows->[$i - 1])) {
            push @$errors, "$name no está ordenado cronológicamente en la fila " . ($i + 1);
            last;
        }
    }
}

sub _check_boundary {
    my ($left_name, $left, $right_name, $right, $errors) = @_;
    return if !@$left || !@$right;
    my $left_last = _row_key($left->[-1]);
    my $right_first = _row_key($right->[0]);
    if ($left_last ge $right_first) {
        push @$errors,
            "$left_name termina en $left_last, pero $right_name comienza en $right_first";
    }
}

sub _range {
    my ($rows) = @_;
    return { count => 0, first => undef, last => undef } if !@$rows;
    return {
        count => scalar(@$rows),
        first => _row_key($rows->[0]),
        last  => _row_key($rows->[-1]),
    };
}

sub _row_key {
    my ($row) = @_;
    return '' if ref($row) ne 'HASH';
    my $timestamp = $row->{confirmation_timestamp} // '';
    return $timestamp;
}

1;
