use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use lib "$FindBin::Bin/Market";
use lib ".";

use Market::ML::TSNEPipeline;

my $dataset_dir = "$FindBin::Bin/datasets/ml_pipeline";
my @input_files = (
    "$dataset_dir/train_trainable.csv",
    "$dataset_dir/validation_trainable.csv",
);
my $output_file = "$dataset_dir/tsne_development_projection.csv";

my $perplexity = @ARGV ? shift(@ARGV) : 30;
my $max_iter   = @ARGV ? shift(@ARGV) : 750;
my $seed       = @ARGV ? shift(@ARGV) : 42;

die "La semilla debe ser un entero\n" if $seed !~ /^-?\d+$/;

for my $file (@input_files) {
    die "No existe $file. Ejecute primero: perl ml_pipeline.pl\n" if !-f $file;
}

my @rows;
for my $file (@input_files) {
    push @rows, @{read_csv_hashes($file)};
}

print "\n========================================\n";
print " t-SNE EXACTO COMPATIBLE - TRAIN + VALIDATION\n";
print "========================================\n";
print "Muestras:       " . scalar(@rows) . "\n";
print "Perplexity:     $perplexity\n";
print "Iteraciones:    $max_iter\n";
print "Semilla:        $seed\n";
print "Backend:        Perl numérico modular (compatible con MXNet 1.9.1)\n";
print "TEST FINAL:     NO UTILIZADO\n";
print "========================================\n";

my $pipeline = Market::ML::TSNEPipeline->new(
    perplexity   => $perplexity,
    max_iter     => $max_iter,
    random_state => $seed,
    verbose      => 2,
);

my $report = $pipeline->run(
    rows        => \@rows,
    output_file => $output_file,
);

print "\n========================================\n";
print " RESULTADO t-SNE\n";
print "========================================\n";
printf "Muestras proyectadas:       %d\n", $report->{samples};
printf "Variables originales:       %d\n", $report->{original_features};
printf "Variables numéricas:        %d\n", $report->{numeric_features};
printf "Variables categóricas:      %d\n", $report->{categorical_features};
printf "Dimensiones tensoriales:    %d\n", $report->{tensor_dimensions};
printf "Perplexity efectiva:        %s\n", $report->{perplexity};
printf "Iteraciones completadas:    %s\n", defined($report->{iterations_completed}) ? $report->{iterations_completed} : 'N/A';
printf "Semilla reproducible:       %s\n", $report->{random_state};
printf "Divergencia KL final:       %s\n", defined($report->{kl_divergence}) ? $report->{kl_divergence} : 'N/A';
print  "Proyección exportada:       $report->{output_file}\n";
print "========================================\n";
print "t-SNE se usa para visualización exploratoria; GMM/HMM trabajarán con las variables originales escaladas.\n";
print "2026_07_20.csv permanece reservado como TEST FINAL.\n";

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
