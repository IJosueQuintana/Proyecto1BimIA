package Market::ML::Evaluation::Procrustes;

use strict;
use warnings;
use Carp qw(croak);

sub compare {
    my ($class, %args) = @_;
    my $reference = $args{reference} // croak "Debe indicar reference\n";
    my $candidate = $args{candidate} // croak "Debe indicar candidate\n";
    _validate($reference, $candidate);

    my $x = _standardize($reference);
    my $y = _standardize($candidate);

    # Solución ortogonal 2D: se evalúa rotación y reflexión y se conserva
    # la transformación con mayor traza, equivalente al Procrustes óptimo.
    my ($a, $b, $c, $d) = (0,0,0,0);
    for my $i (0 .. $#$x) {
        $a += $y->[$i][0] * $x->[$i][0];
        $b += $y->[$i][0] * $x->[$i][1];
        $c += $y->[$i][1] * $x->[$i][0];
        $d += $y->[$i][1] * $x->[$i][1];
    }

    my $theta_rot = atan2($b - $c, $a + $d);
    my $theta_ref = atan2($b + $c, $a - $d);
    my @candidates = (
        _rotation($theta_rot, 0),
        _rotation($theta_ref, 1),
    );

    my ($best, $best_sse);
    for my $r (@candidates) {
        my $sse = 0.0;
        my @aligned;
        for my $i (0 .. $#$y) {
            my $u = $y->[$i][0] * $r->[0][0] + $y->[$i][1] * $r->[1][0];
            my $v = $y->[$i][0] * $r->[0][1] + $y->[$i][1] * $r->[1][1];
            push @aligned, [$u, $v];
            $sse += ($x->[$i][0] - $u) ** 2 + ($x->[$i][1] - $v) ** 2;
        }
        if (!defined($best_sse) || $sse < $best_sse) {
            $best_sse = $sse;
            $best = { rotation => $r, aligned => \@aligned };
        }
    }

    # Ambos mapas tienen norma Frobenius 1; disparity queda aproximadamente 0..2.
    my $disparity = $best_sse;
    my $similarity = 1.0 - $disparity / 2.0;
    $similarity = 0 if $similarity < 0;
    $similarity = 1 if $similarity > 1;

    return {
        disparity => $disparity,
        similarity => $similarity,
        aligned_candidate => $best->{aligned},
        transformation => $best->{rotation},
    };
}

sub _standardize {
    my ($m) = @_;
    my $n = @$m;
    my ($mx,$my)=(0,0);
    for (@$m) { $mx += $_->[0]; $my += $_->[1]; }
    $mx /= $n; $my /= $n;
    my (@out,$norm2);
    $norm2 = 0.0;
    for (@$m) {
        my ($x,$y)=($_->[0]-$mx,$_->[1]-$my);
        push @out, [$x,$y];
        $norm2 += $x*$x+$y*$y;
    }
    croak "No se puede aplicar Procrustes a una proyección degenerada\n" if $norm2 < 1e-20;
    my $norm=sqrt($norm2);
    $_->[0]/=$norm, $_->[1]/=$norm for @out;
    return \@out;
}

sub _rotation {
    my ($theta,$reflection)=@_;
    my ($co,$si)=(cos($theta),sin($theta));
    return $reflection
        ? [[$co,$si],[$si,-$co]]
        : [[$co,$si],[-$si,$co]];
}

sub _validate {
    my ($a,$b)=@_;
    croak "Las proyecciones deben ser ARRAY y no estar vacías\n"
        if ref($a) ne 'ARRAY' || ref($b) ne 'ARRAY' || !@$a || !@$b;
    croak "Las proyecciones deben contener el mismo número de puntos\n" if @$a != @$b;
    for my $m ($a,$b) {
        for my $p (@$m) {
            croak "Procrustes requiere coordenadas bidimensionales\n"
                if ref($p) ne 'ARRAY' || @$p != 2;
        }
    }
}

1;
