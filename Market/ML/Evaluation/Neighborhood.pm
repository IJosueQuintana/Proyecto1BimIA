package Market::ML::Evaluation::Neighborhood;

use strict;
use warnings;
use Carp qw(croak);

sub pairwise_squared {
    my ($class, $vectors) = @_;
    _validate_vectors($vectors);
    my $n = @$vectors;
    my @d = map { [(0) x $n] } 1 .. $n;
    for my $i (0 .. $n - 1) {
        for my $j ($i + 1 .. $n - 1) {
            my $sum = 0.0;
            for my $m (0 .. $#{$vectors->[$i]}) {
                my $delta = $vectors->[$i][$m] - $vectors->[$j][$m];
                $sum += $delta * $delta;
            }
            $d[$i][$j] = $sum;
            $d[$j][$i] = $sum;
        }
    }
    return \@d;
}

sub rankings {
    my ($class, $distances) = @_;
    croak "distances debe ser una matriz cuadrada\n"
        if ref($distances) ne 'ARRAY' || !@$distances;
    my $n = @$distances;
    my (@ordered, @rank);
    for my $i (0 .. $n - 1) {
        croak "distances debe ser una matriz cuadrada\n"
            if ref($distances->[$i]) ne 'ARRAY' || @{$distances->[$i]} != $n;
        my @idx = sort {
            $distances->[$i][$a] <=> $distances->[$i][$b] || $a <=> $b
        } grep { $_ != $i } 0 .. $n - 1;
        $ordered[$i] = \@idx;
        my @r = (0) x $n;
        for my $pos (0 .. $#idx) {
            $r[$idx[$pos]] = $pos + 1; # rango 1-based
        }
        $rank[$i] = \@r;
    }
    return { ordered => \@ordered, rank => \@rank };
}

sub neighbors {
    my ($class, %args) = @_;
    my $ranking = $args{ranking} // croak "Debe indicar ranking\n";
    my $k = $args{k} // croak "Debe indicar k\n";
    my $n = @{$ranking->{ordered} // []};
    _validate_k($n, $k);
    my @sets;
    for my $i (0 .. $n - 1) {
        my %set = map { $_ => 1 } @{$ranking->{ordered}[$i]}[0 .. $k - 1];
        $sets[$i] = \%set;
    }
    return \@sets;
}

sub preservation {
    my ($class, %args) = @_;
    my $original = $args{original_ranking} // croak "Debe indicar original_ranking\n";
    my $embedded = $args{embedded_ranking} // croak "Debe indicar embedded_ranking\n";
    my $k = $args{k} // croak "Debe indicar k\n";
    my $n = @{$original->{ordered} // []};
    croak "Los rankings deben contener el mismo número de muestras\n"
        if $n != @{$embedded->{ordered} // []};
    _validate_k($n, $k);

    my $sum = 0.0;
    for my $i (0 .. $n - 1) {
        my %a = map { $_ => 1 } @{$original->{ordered}[$i]}[0 .. $k - 1];
        my $shared = 0;
        for my $j (@{$embedded->{ordered}[$i]}[0 .. $k - 1]) {
            $shared++ if $a{$j};
        }
        $sum += $shared / $k;
    }
    return $sum / $n;
}

sub _validate_vectors {
    my ($vectors) = @_;
    croak "vectors debe ser ARRAY y no puede estar vacío\n"
        if ref($vectors) ne 'ARRAY' || !@$vectors;
    my $dims = ref($vectors->[0]) eq 'ARRAY' ? @{$vectors->[0]} : 0;
    croak "Cada vector debe ser ARRAY y tener dimensiones\n" if !$dims;
    for my $v (@$vectors) {
        croak "Todos los vectores deben tener la misma dimensión\n"
            if ref($v) ne 'ARRAY' || @$v != $dims;
    }
}

sub _validate_k {
    my ($n, $k) = @_;
    croak "k debe ser entero positivo\n" if $k !~ /^\d+$/ || $k < 1;
    croak "k debe ser menor que el número de muestras ($n)\n" if $k >= $n;
}

1;
