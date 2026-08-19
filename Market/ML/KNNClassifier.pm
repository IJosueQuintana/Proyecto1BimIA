package Market::ML::KNNClassifier;

use strict;
use warnings;

sub new {
    my ($class, %args) = @_;
    return bless {
        k             => $args{k} // 5,
        labels        => $args{labels} // [qw(RUN GRAB SWEEP)],
        train_vectors => undef,
        train_labels  => undef,
    }, $class;
}

sub fit {
    my ($self, %args) = @_;
    my $vectors = $args{vectors} // [];
    my $labels  = $args{labels}  // [];
    die "vectors debe ser ARRAY\n" if ref($vectors) ne 'ARRAY';
    die "labels debe ser ARRAY\n" if ref($labels) ne 'ARRAY';
    die "No se puede entrenar k-NN con cero filas\n" if !@$vectors;
    die "Cantidad distinta de vectores y etiquetas\n" if @$vectors != @$labels;
    die "k debe ser mayor que cero\n" if $self->{k} < 1;

    my $dimension = scalar(@{$vectors->[0]});
    for my $vector (@$vectors) {
        die "Todos los vectores deben tener la misma dimensión\n"
            if ref($vector) ne 'ARRAY' || @$vector != $dimension;
    }

    $self->{train_vectors} = [map { [@$_] } @$vectors];
    $self->{train_labels}  = [map { uc($_ // '') } @$labels];
    return $self;
}

sub predict {
    my ($self, %args) = @_;
    my $vectors = $args{vectors} // [];
    die "k-NN todavía no fue entrenado\n" if ref($self->{train_vectors}) ne 'ARRAY';
    die "vectors debe ser ARRAY\n" if ref($vectors) ne 'ARRAY';
    return [map { $self->_predict_one($_) } @$vectors];
}

sub _predict_one {
    my ($self, $vector) = @_;
    my @distances;
    for my $i (0 .. $#{$self->{train_vectors}}) {
        my $distance = _squared_euclidean($vector, $self->{train_vectors}[$i]);
        push @distances, {
            distance => $distance,
            label    => $self->{train_labels}[$i],
            index    => $i,
        };
    }
    @distances = sort {
        $a->{distance} <=> $b->{distance} || $a->{index} <=> $b->{index}
    } @distances;

    my $neighbor_count = $self->{k} < @distances ? $self->{k} : scalar(@distances);
    my (%votes, %distance_sum);
    for my $i (0 .. $neighbor_count - 1) {
        my $neighbor = $distances[$i];
        $votes{$neighbor->{label}}++;
        $distance_sum{$neighbor->{label}} += $neighbor->{distance};
    }

    my %label_order = map { $self->{labels}[$_] => $_ } 0 .. $#{$self->{labels}};
    my @ranked = sort {
        ($votes{$b} // 0) <=> ($votes{$a} // 0)
        || ($distance_sum{$a} // 0) <=> ($distance_sum{$b} // 0)
        || ($label_order{$a} // 999) <=> ($label_order{$b} // 999)
    } keys %votes;
    return $ranked[0];
}

sub _squared_euclidean {
    my ($a, $b) = @_;
    die "Vector de evaluación inválido\n" if ref($a) ne 'ARRAY';
    die "Dimensiones incompatibles en k-NN\n" if @$a != @$b;
    my $sum = 0;
    for my $i (0 .. $#$a) {
        my $difference = $a->[$i] - $b->[$i];
        $sum += $difference * $difference;
    }
    return $sum;
}

1;
