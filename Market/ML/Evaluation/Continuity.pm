package Market::ML::Evaluation::Continuity;

use strict;
use warnings;
use Carp qw(croak);

sub score {
    my ($class, %args) = @_;
    my $original = $args{original_ranking} // croak "Debe indicar original_ranking\n";
    my $embedded = $args{embedded_ranking} // croak "Debe indicar embedded_ranking\n";
    my $k = $args{k} // croak "Debe indicar k\n";
    my $n = @{$original->{ordered} // []};
    croak "Los rankings deben contener el mismo número de muestras\n"
        if $n != @{$embedded->{ordered} // []};
    croak "k inválido para Continuity\n" if $k < 1 || $k >= $n;

    my $den = $n * $k * (2 * $n - 3 * $k - 1);
    croak "k demasiado grande para la fórmula de Continuity\n" if $den <= 0;

    my $penalty = 0.0;
    for my $i (0 .. $n - 1) {
        my %emb_k = map { $_ => 1 } @{$embedded->{ordered}[$i]}[0 .. $k - 1];
        for my $j (@{$original->{ordered}[$i]}[0 .. $k - 1]) {
            next if $emb_k{$j};
            $penalty += $embedded->{rank}[$i][$j] - $k;
        }
    }
    my $score = 1.0 - (2.0 * $penalty / $den);
    return _clamp($score);
}

sub _clamp { my ($x)=@_; return 0 if $x<0; return 1 if $x>1; return $x; }
1;
