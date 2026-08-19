use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use lib "$FindBin::Bin/Market";
use lib ".";
use Time::HiRes qw(time);

use Market::ML::FeatureSchema;
use Market::ML::StandardScaler;
use Market::ML::TSNE;

my $perplexity = @ARGV ? shift(@ARGV) : 30;
my $max_iter   = @ARGV ? shift(@ARGV) : 750;
my $k_neighbors = @ARGV ? shift(@ARGV) : 10;
my @seeds = @ARGV ? @ARGV : (42, 7, 123);

die "Uso: perl tsne_seed_compare.pl [perplexity] [iteraciones] [k] [semillas...]\n"
    if $perplexity !~ /^\d+(?:\.\d+)?$/ || $max_iter !~ /^\d+$/ || $k_neighbors !~ /^\d+$/;
die "Indique al menos dos semillas\n" if @seeds < 2;
for my $seed (@seeds) {
    die "La semilla '$seed' debe ser entera\n" if $seed !~ /^-?\d+$/;
}

my $dataset_dir = "$FindBin::Bin/datasets/ml_pipeline";
my @input_files = (
    "$dataset_dir/train_trainable.csv",
    "$dataset_dir/validation_trainable.csv",
);
for my $file (@input_files) {
    die "No existe $file. Ejecute primero: perl ml_pipeline.pl\n" if !-f $file;
}

my @rows;
for my $file (@input_files) {
    push @rows, @{read_csv_hashes($file)};
}

my $features = Market::ML::FeatureSchema->select_feature_columns(rows => \@rows);
my $scaler = Market::ML::StandardScaler->new(feature_columns => $features);
my $vectors = $scaler->fit_transform(rows => \@rows);

my $n = scalar(@$vectors);
die "k debe ser menor que el número de muestras\n" if $k_neighbors >= $n;
die "perplexity debe ser menor que el número de muestras\n" if $perplexity >= $n;

print "\n========================================\n";
print " ESTABILIDAD DE t-SNE FRENTE A LA SEMILLA\n";
print "========================================\n";
print "Muestras:       $n\n";
print "Perplexity:     $perplexity\n";
print "Iteraciones:    $max_iter\n";
print "Vecinos k:      $k_neighbors\n";
print "Semillas:       " . join(', ', @seeds) . "\n";
print "TEST FINAL:     NO UTILIZADO\n";
print "========================================\n";

my %runs;
for my $seed (@seeds) {
    print "\n[SEMILLA $seed] Ejecutando t-SNE...\n";
    my $start = time;
    my $tsne = Market::ML::TSNE->new(
        n_components  => 2,
        perplexity    => $perplexity,
        max_iter      => $max_iter,
        random_state  => $seed,
        learning_rate => 'auto',
        verbose       => 0,
        n_iter_check  => 25,
    );
    my $embedding = $tsne->fit_transform($vectors);
    my $elapsed = time - $start;
    $runs{$seed} = {
        embedding => $embedding,
        kl => $tsne->{kl_divergence_},
        elapsed => $elapsed,
        distances => condensed_distances($embedding),
        neighbors => nearest_neighbors($embedding, $k_neighbors),
    };
    printf "  KL final: %.8f\n", $runs{$seed}{kl};
    printf "  Tiempo:   %.2f s\n", $elapsed;
}

print "\n========================================\n";
print " COMPARACIÓN ENTRE SEMILLAS\n";
print "========================================\n";

my @pair_results;
for my $a_idx (0 .. $#seeds - 1) {
    for my $b_idx ($a_idx + 1 .. $#seeds) {
        my ($a, $b) = ($seeds[$a_idx], $seeds[$b_idx]);
        my $corr = pearson_correlation($runs{$a}{distances}, $runs{$b}{distances});
        my $overlap = mean_neighbor_overlap(
            $runs{$a}{neighbors},
            $runs{$b}{neighbors},
            $k_neighbors,
        );
        my $kl_delta = abs($runs{$a}{kl} - $runs{$b}{kl});
        push @pair_results, {
            a => $a, b => $b,
            corr => $corr,
            overlap => $overlap,
            kl_delta => $kl_delta,
        };
        printf "%s vs %s: correlación_distancias=%.4f  vecinos_compartidos=%.2f%%  |ΔKL|=%.6f\n",
            $a, $b, $corr, 100 * $overlap, $kl_delta;
    }
}

my $mean_corr = average(map { $_->{corr} } @pair_results);
my $mean_overlap = average(map { $_->{overlap} } @pair_results);
my $mean_kl_delta = average(map { $_->{kl_delta} } @pair_results);

print "----------------------------------------\n";
printf "Correlación media de distancias: %.4f\n", $mean_corr;
printf "Vecinos locales compartidos:     %.2f%%\n", 100 * $mean_overlap;
printf "Diferencia KL media:              %.6f\n", $mean_kl_delta;
print "----------------------------------------\n";

my ($level, $verdict);
if ($mean_corr >= 0.90 && $mean_overlap >= 0.70) {
    $level = 'BAJA';
    $verdict = 'La semilla cambia principalmente la orientación/posición, pero la estructura global y local es muy estable.';
} elsif ($mean_corr >= 0.75 && $mean_overlap >= 0.50) {
    $level = 'MODERADA';
    $verdict = 'La semilla modifica parte de la organización local, aunque conserva una estructura general semejante.';
} else {
    $level = 'ALTA';
    $verdict = 'La proyección depende considerablemente de la inicialización; no debe interpretarse una sola semilla como evidencia suficiente.';
}

print "INFLUENCIA DE LA SEMILLA: $level\n";
print "$verdict\n";
print "========================================\n";

sub condensed_distances {
    my ($embedding) = @_;
    my @d;
    for my $i (0 .. $#$embedding - 1) {
        for my $j ($i + 1 .. $#$embedding) {
            my $dx = $embedding->[$i][0] - $embedding->[$j][0];
            my $dy = $embedding->[$i][1] - $embedding->[$j][1];
            push @d, sqrt($dx * $dx + $dy * $dy);
        }
    }
    return \@d;
}

sub nearest_neighbors {
    my ($embedding, $k) = @_;
    my @neighbors;
    for my $i (0 .. $#$embedding) {
        my @dist;
        for my $j (0 .. $#$embedding) {
            next if $i == $j;
            my $dx = $embedding->[$i][0] - $embedding->[$j][0];
            my $dy = $embedding->[$i][1] - $embedding->[$j][1];
            push @dist, [$dx * $dx + $dy * $dy, $j];
        }
        @dist = sort { $a->[0] <=> $b->[0] || $a->[1] <=> $b->[1] } @dist;
        $neighbors[$i] = [map { $dist[$_][1] } 0 .. $k - 1];
    }
    return \@neighbors;
}

sub mean_neighbor_overlap {
    my ($a, $b, $k) = @_;
    my $sum = 0;
    for my $i (0 .. $#$a) {
        my %seen = map { $_ => 1 } @{$a->[$i]};
        my $shared = 0;
        $shared++ for grep { $seen{$_} } @{$b->[$i]};
        $sum += $shared / $k;
    }
    return $sum / scalar(@$a);
}

sub pearson_correlation {
    my ($x, $y) = @_;
    die "Vectores incompatibles para correlación\n" if @$x != @$y || !@$x;
    my $n = scalar @$x;
    my ($sx, $sy) = (0, 0);
    $sx += $_ for @$x;
    $sy += $_ for @$y;
    my ($mx, $my) = ($sx / $n, $sy / $n);
    my ($num, $dx2, $dy2) = (0, 0, 0);
    for my $i (0 .. $n - 1) {
        my $dx = $x->[$i] - $mx;
        my $dy = $y->[$i] - $my;
        $num += $dx * $dy;
        $dx2 += $dx * $dx;
        $dy2 += $dy * $dy;
    }
    return 0 if $dx2 <= 0 || $dy2 <= 0;
    return $num / sqrt($dx2 * $dy2);
}

sub average {
    my @values = @_;
    return 0 if !@values;
    my $sum = 0;
    $sum += $_ for @values;
    return $sum / @values;
}

sub read_csv_hashes {
    my ($file) = @_;
    open my $fh, '<:encoding(UTF-8)', $file
        or die "No se puede leer '$file': $!\n";
    my $header_line = <$fh>;
    die "CSV sin cabecera: $file\n" if !defined $header_line;
    $header_line =~ s/[\r\n]+$//;
    my @headers = parse_csv_line($header_line);
    my @data;
    while (my $line = <$fh>) {
        $line =~ s/[\r\n]+$//;
        next if $line eq '';
        my @values = parse_csv_line($line);
        my %row;
        @row{@headers} = @values;
        push @data, \%row;
    }
    close $fh;
    return \@data;
}

sub parse_csv_line {
    my ($line) = @_;
    my @fields;
    my $field = '';
    my $quoted = 0;
    my @chars = split //, $line;
    for (my $i = 0; $i < @chars; $i++) {
        my $ch = $chars[$i];
        if ($quoted) {
            if ($ch eq '"') {
                if ($i + 1 < @chars && $chars[$i + 1] eq '"') {
                    $field .= '"';
                    $i++;
                } else {
                    $quoted = 0;
                }
            } else {
                $field .= $ch;
            }
        } else {
            if ($ch eq '"') {
                $quoted = 1;
            } elsif ($ch eq ',') {
                push @fields, $field;
                $field = '';
            } else {
                $field .= $ch;
            }
        }
    }
    push @fields, $field;
    return @fields;
}
