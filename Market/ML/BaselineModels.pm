package Market::ML::BaselineModels;

use strict;
use warnings;

sub new {
    my ($class, %args) = @_;
    return bless {
        seed => $args{seed} // 42,
    }, $class;
}

sub zero_rule_predict {
    my ($self, %args) = @_;
    my $train_rows = $args{train_rows} // [];
    my $test_rows  = $args{test_rows}  // [];

    my %count;
    for my $row (@$train_rows) {
        next if ref($row) ne 'HASH';
        my $target = uc($row->{target} // '');
        $count{$target}++ if $target ne '';
    }

    die "No hay targets de entrenamiento para Zero Rule\n" if !%count;

    my ($majority) = sort {
        $count{$b} <=> $count{$a} || $a cmp $b
    } keys %count;

    return ([ map { $majority } @$test_rows ], $majority, \%count);
}

sub random_predict {
    my ($self, %args) = @_;
    my $train_rows = $args{train_rows} // [];
    my $test_rows  = $args{test_rows}  // [];
    my $seed       = defined $args{seed} ? $args{seed} : $self->{seed};

    my @population;
    for my $row (@$train_rows) {
        next if ref($row) ne 'HASH';
        my $target = uc($row->{target} // '');
        push @population, $target if $target ne '';
    }

    die "No hay targets de entrenamiento para Random Prediction\n"
        if !@population;

    srand($seed);
    my @predictions = map {
        $population[int(rand(@population))]
    } @$test_rows;

    return \@predictions;
}

1;
