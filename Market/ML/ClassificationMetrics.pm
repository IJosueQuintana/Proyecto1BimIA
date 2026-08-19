package Market::ML::ClassificationMetrics;

use strict;
use warnings;
use List::Util qw(sum);

sub new {
    my ($class, %args) = @_;
    return bless {
        labels => $args{labels} // [qw(RUN GRAB SWEEP)],
    }, $class;
}

sub evaluate {
    my ($self, %args) = @_;
    my $actual    = $args{actual}    // [];
    my $predicted = $args{predicted} // [];

    die "actual debe ser ARRAY\n" if ref($actual) ne 'ARRAY';
    die "predicted debe ser ARRAY\n" if ref($predicted) ne 'ARRAY';
    die "actual y predicted deben tener igual longitud\n"
        if @$actual != @$predicted;

    my @labels = @{$self->{labels}};
    my %matrix;
    my $correct = 0;

    for my $i (0 .. $#$actual) {
        my $a = uc($actual->[$i] // '');
        my $p = uc($predicted->[$i] // '');
        $matrix{$a}{$p}++;
        $correct++ if $a eq $p;
    }

    my %per_class;
    for my $label (@labels) {
        my $tp = $matrix{$label}{$label} // 0;
        my $fp = 0;
        my $fn = 0;
        my $support = 0;

        for my $other (@labels) {
            $support += $matrix{$label}{$other} // 0;
            $fp += $matrix{$other}{$label} // 0 if $other ne $label;
            $fn += $matrix{$label}{$other} // 0 if $other ne $label;
        }

        my $precision = ($tp + $fp) ? $tp / ($tp + $fp) : 0;
        my $recall    = ($tp + $fn) ? $tp / ($tp + $fn) : 0;
        my $f1        = ($precision + $recall)
            ? 2 * $precision * $recall / ($precision + $recall)
            : 0;

        $per_class{$label} = {
            precision => $precision,
            recall    => $recall,
            f1        => $f1,
            support   => $support,
        };
    }

    my $n = scalar @$actual;
    my $accuracy = $n ? $correct / $n : 0;
    my $macro_f1 = @labels
        ? sum(map { $per_class{$_}{f1} } @labels) / scalar(@labels)
        : 0;

    return {
        total      => $n,
        correct    => $correct,
        accuracy   => $accuracy,
        macro_f1   => $macro_f1,
        labels     => \@labels,
        matrix     => \%matrix,
        per_class  => \%per_class,
    };
}

sub print_report {
    my ($self, $name, $report) = @_;
    my @labels = @{$report->{labels} // $self->{labels}};

    print "\n========================================\n";
    print " $name\n";
    print "========================================\n";
    printf "Muestras:  %d\n", $report->{total} // 0;
    printf "Accuracy:  %.4f (%.2f%%)\n",
        $report->{accuracy} // 0,
        100 * ($report->{accuracy} // 0);
    printf "Macro F1:  %.4f\n", $report->{macro_f1} // 0;

    print "\nMATRIZ DE CONFUSIÓN (real x predicho)\n";
    printf "%-10s", 'REAL\\PRED';
    printf "%10s", $_ for @labels;
    print "\n";
    for my $actual (@labels) {
        printf "%-10s", $actual;
        printf "%10d", ($report->{matrix}{$actual}{$_} // 0) for @labels;
        print "\n";
    }

    print "\nMÉTRICAS POR CLASE\n";
    printf "%-10s %10s %10s %10s %10s\n",
        'CLASE', 'PRECISION', 'RECALL', 'F1', 'SOPORTE';
    for my $label (@labels) {
        my $m = $report->{per_class}{$label};
        printf "%-10s %10.4f %10.4f %10.4f %10d\n",
            $label,
            $m->{precision},
            $m->{recall},
            $m->{f1},
            $m->{support};
    }
    print "========================================\n";
}

1;
