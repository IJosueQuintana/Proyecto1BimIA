package Market::ML::SequentialLeakageAuditor;

use strict;
use warnings;
use Carp qw(croak);
use List::Util qw(min max sum);
use Market::ML::SequentialFeatureSchema;

sub new { bless {}, shift }

sub audit {
    my ($self, %args) = @_;
    my $rows = $args{rows} // [];
    croak "rows debe ser ARRAY\n" if ref($rows) ne 'ARRAY';
    croak "No hay filas para auditar\n" if !@$rows;

    my @features = @{Market::ML::SequentialFeatureSchema->feature_columns};
    my %forbidden = map { $_ => 1 } qw(state_label event_target outcome_target target);
    my @forbidden_in_x = grep { $forbidden{$_} } @features;
    my (@constant, @non_finite, %stats);

    for my $feature (@features) {
        my (@values, $bad);
        for my $row (@$rows) {
            my $raw = $row->{$feature};
            if (!defined($raw) || $raw eq '' || $raw =~ /^(?:nan|inf|-inf)$/i) {
                $bad++;
                next;
            }
            push @values, 0 + $raw;
        }
        push @non_finite, $feature if $bad;
        next if !@values;
        my $mean = sum(@values) / @values;
        my $var = sum(map { ($_ - $mean) ** 2 } @values) / @values;
        my $minimum = min(@values);
        my $maximum = max(@values);
        push @constant, $feature if abs($maximum - $minimum) < 1e-12;
        $stats{$feature} = {
            mean => $mean,
            variance => $var,
            min => $minimum,
            max => $maximum,
            missing_or_non_finite => $bad || 0,
        };
    }

    return {
        rows => scalar(@$rows),
        features => \@features,
        feature_count => scalar(@features),
        forbidden_in_x => \@forbidden_in_x,
        constant => \@constant,
        non_finite => \@non_finite,
        stats => \%stats,
        causal_contract => 'X usa únicamente columnas definidas por SequentialFeatureSchema; etiquetas y targets están excluidos.',
    };
}

sub print_report {
    my ($self, $report) = @_;
    print "SEQUENTIAL HMM FEATURE AUDIT\n";
    print "Rows: $report->{rows}\n";
    print "Features: $report->{feature_count}\n";
    print "Forbidden columns in X: ", (@{$report->{forbidden_in_x}} ? join(', ', @{$report->{forbidden_in_x}}) : 'none'), "\n";
    print "Constant features: ", (@{$report->{constant}} ? join(', ', @{$report->{constant}}) : 'none'), "\n";
    print "Missing/non-finite features: ", (@{$report->{non_finite}} ? join(', ', @{$report->{non_finite}}) : 'none'), "\n";
    print "Causality: $report->{causal_contract}\n";
}

1;
