use strict;
use warnings;
use utf8;
use FindBin;
use lib $FindBin::Bin;
use lib "$FindBin::Bin/Market";
use lib ".";
use Time::HiRes qw(time);

use Market::ML::FeatureSchema;
use Market::ML::StandardScaler;
use Market::ML::TSNE;
use Market::ML::Evaluation::Neighborhood;
use Market::ML::Evaluation::Trustworthiness;
use Market::ML::Evaluation::Continuity;
use Market::ML::Evaluation::Procrustes;

my $perplexity = @ARGV ? shift @ARGV : 30;
my $max_iter   = @ARGV ? shift @ARGV : 750;
my @seeds      = @ARGV ? @ARGV : (42, 7, 123);
my @k_values   = (5, 10, 20);

for ($perplexity, $max_iter, @seeds) {
    die "Los parámetros deben ser enteros\n" if !defined($_) || $_ !~ /^-?\d+$/;
}
die "Debe indicar al menos dos semillas\n" if @seeds < 2;

my $dataset_dir = "$FindBin::Bin/datasets/ml_pipeline";
my @input_files = (
    "$dataset_dir/train_trainable.csv",
    "$dataset_dir/validation_trainable.csv",
);
for my $file (@input_files) {
    die "No existe $file. Ejecute primero: perl ml_pipeline.pl\n" if !-f $file;
}

my @rows;
push @rows, @{read_csv_hashes($_)} for @input_files;
die "No existen suficientes muestras\n" if @rows < 3;

my $features = Market::ML::FeatureSchema->select_feature_columns(rows => \@rows);
my $scaler = Market::ML::StandardScaler->new(feature_columns => $features);
my $vectors = $scaler->fit_transform(rows => \@rows);
my $n = @$vectors;
$perplexity = int(($n - 1) / 3) if $perplexity >= $n;
@k_values = grep { $_ < $n && (2 * $n - 3 * $_ - 1) > 0 } @k_values;
die "No hay valores k válidos para $n muestras\n" if !@k_values;

print "\n========================================\n";
print " VALIDACIÓN DEL EMBEDDING t-SNE\n";
print "========================================\n";
print "Muestras:              $n\n";
print "Variables originales:  " . scalar(@$features) . "\n";
print "Dimensiones escaladas: " . scalar(@{$scaler->output_features}) . "\n";
print "Perplexity:            $perplexity\n";
print "Iteraciones:           $max_iter\n";
print "Semillas:              " . join(', ', @seeds) . "\n";
print "TEST FINAL:            NO UTILIZADO\n";
print "========================================\n";

print "\n[1/3] Calculando vecindarios del espacio original...\n";
my $original_dist = Market::ML::Evaluation::Neighborhood->pairwise_squared($vectors);
my $original_rank = Market::ML::Evaluation::Neighborhood->rankings($original_dist);

my %result;
for my $seed (@seeds) {
    print "\n[SEMILLA $seed] Ejecutando t-SNE...\n";
    my $start = time;
    my $tsne = Market::ML::TSNE->new(
        n_components => 2,
        perplexity => $perplexity,
        max_iter => $max_iter,
        random_state => $seed,
        learning_rate => 'auto',
        verbose => 0,
        n_iter_check => 25,
    );
    my $embedding = $tsne->fit_transform($vectors);
    my $elapsed = time - $start;

    my $embedded_dist = Market::ML::Evaluation::Neighborhood->pairwise_squared($embedding);
    my $embedded_rank = Market::ML::Evaluation::Neighborhood->rankings($embedded_dist);

    my (%trust, %continuity, %preservation);
    for my $k (@k_values) {
        $trust{$k} = Market::ML::Evaluation::Trustworthiness->score(
            original_ranking => $original_rank,
            embedded_ranking => $embedded_rank,
            k => $k,
        );
        $continuity{$k} = Market::ML::Evaluation::Continuity->score(
            original_ranking => $original_rank,
            embedded_ranking => $embedded_rank,
            k => $k,
        );
        $preservation{$k} = Market::ML::Evaluation::Neighborhood->preservation(
            original_ranking => $original_rank,
            embedded_ranking => $embedded_rank,
            k => $k,
        );
    }

    $result{$seed} = {
        embedding => $embedding,
        ranking => $embedded_rank,
        kl => $tsne->{kl_divergence_},
        seconds => $elapsed,
        trust => \%trust,
        continuity => \%continuity,
        preservation => \%preservation,
    };

    printf "  KL final:  %.8f\n", $result{$seed}{kl};
    printf "  Tiempo:    %.2f s\n", $elapsed;
    for my $k (@k_values) {
        printf "  k=%-2d  Trustworthiness=%.4f  Continuity=%.4f  Vecinos originales conservados=%.2f%%\n",
            $k, $trust{$k}, $continuity{$k}, 100*$preservation{$k};
    }
}

print "\n========================================\n";
print " COMPARACIÓN ENTRE SEMILLAS\n";
print "========================================\n";
my (@similarities, @seed_neighbor, @kl_diffs);
for my $i (0 .. $#seeds - 1) {
    for my $j ($i + 1 .. $#seeds) {
        my ($a,$b)=($seeds[$i],$seeds[$j]);
        my $proc = Market::ML::Evaluation::Procrustes->compare(
            reference => $result{$a}{embedding},
            candidate => $result{$b}{embedding},
        );
        my $shared = Market::ML::Evaluation::Neighborhood->preservation(
            original_ranking => $result{$a}{ranking},
            embedded_ranking => $result{$b}{ranking},
            k => 10 < $n ? 10 : $k_values[-1],
        );
        my $dkl = abs($result{$a}{kl} - $result{$b}{kl});
        push @similarities, $proc->{similarity};
        push @seed_neighbor, $shared;
        push @kl_diffs, $dkl;
        printf "%s vs %s: similitud_Procrustes=%.4f  vecinos_compartidos=%.2f%%  |ΔKL|=%.6f\n",
            $a,$b,$proc->{similarity},100*$shared,$dkl;
    }
}

my $avg_proc = average(\@similarities);
my $avg_seed_neighbors = average(\@seed_neighbor);
my $avg_kl = average(\@kl_diffs);
my $avg_trust10 = average([map { $result{$_}{trust}{10} // $result{$_}{trust}{$k_values[-1]} } @seeds]);
my $avg_cont10 = average([map { $result{$_}{continuity}{10} // $result{$_}{continuity}{$k_values[-1]} } @seeds]);

print "----------------------------------------\n";
printf "Trustworthiness media (k=10): %.4f\n", $avg_trust10;
printf "Continuity media (k=10):      %.4f\n", $avg_cont10;
printf "Similitud Procrustes media:    %.4f\n", $avg_proc;
printf "Vecinos entre semillas (k=10): %.2f%%\n", 100*$avg_seed_neighbors;
printf "Diferencia KL media:           %.6f\n", $avg_kl;
print "----------------------------------------\n";

my ($quality,$influence,$decision);
if ($avg_trust10 >= 0.95 && $avg_cont10 >= 0.95) { $quality='EXCELENTE'; }
elsif ($avg_trust10 >= 0.90 && $avg_cont10 >= 0.90) { $quality='BUENA'; }
elsif ($avg_trust10 >= 0.80 && $avg_cont10 >= 0.80) { $quality='ACEPTABLE'; }
else { $quality='DÉBIL'; }

# El veredicto usa tanto alineación global como estabilidad local.
if ($avg_proc >= 0.85 && $avg_seed_neighbors >= 0.70) { $influence='BAJA'; }
elsif ($avg_proc >= 0.60 && $avg_seed_neighbors >= 0.40) { $influence='MODERADA'; }
else { $influence='ALTA'; }

if ($quality eq 'EXCELENTE' || $quality eq 'BUENA') {
    $decision = $influence eq 'ALTA'
        ? 'El embedding preserva los datos, pero una sola semilla no representa una solución estable.'
        : 'El embedding preserva adecuadamente la estructura y presenta estabilidad suficiente.';
} else {
    $decision = 'La proyección todavía no preserva suficientemente la estructura original; conviene ajustar t-SNE antes de interpretarla.';
}

print "CALIDAD DEL EMBEDDING:       $quality\n";
print "INFLUENCIA DE LA SEMILLA:    $influence\n";
print "$decision\n";
print "========================================\n";

sub average { my ($a)=@_; return 0 if !@$a; my $s=0; $s+=$_ for @$a; return $s/@$a; }

sub read_csv_hashes {
    my ($file) = @_;
    open my $fh, '<:encoding(UTF-8)', $file or die "No se puede leer '$file': $!\n";
    my $header = <$fh>; die "CSV sin cabecera: $file\n" if !defined $header;
    $header =~ s/[\r\n]+$//; my @h = parse_csv_line($header); my @rows;
    while (my $line = <$fh>) {
        $line =~ s/[\r\n]+$//; next if $line eq '';
        my @v = parse_csv_line($line); my %r; @r{@h}=@v; push @rows,\%r;
    }
    close $fh; return \@rows;
}

sub parse_csv_line {
    my ($line)=@_; my (@fields,$field); $field=''; my $quoted=0;
    for(my $i=0;$i<length($line);$i++){
        my $ch=substr($line,$i,1);
        if($quoted){ if($ch eq '"'){ if($i+1<length($line)&&substr($line,$i+1,1) eq '"'){$field.='"';$i++}else{$quoted=0} } else{$field.=$ch} }
        else{ if($ch eq '"'){$quoted=1}elsif($ch eq ','){push @fields,$field;$field=''}else{$field.=$ch} }
    }
    push @fields,$field; return @fields;
}
