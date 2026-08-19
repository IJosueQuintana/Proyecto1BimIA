use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use lib "$FindBin::Bin/Market";
use lib ".";

use File::Path qw(make_path);
use Market::ML::DatasetAuditor;

my $base = "$FindBin::Bin/datasets/ml_pipeline";
my $train_file = "$base/train_trainable.csv";
my $validation_file = "$base/validation_trainable.csv";
my $output_dir = "$base/audit";

for my $file ($train_file, $validation_file) {
    die "No existe $file. Ejecute primero: perl ml_pipeline.pl\n" if !-f $file;
}

my $auditor = Market::ML::DatasetAuditor->new(
    labels => [qw(RUN GRAB SWEEP)],
    high_corr_threshold => 0.90,
);

print "\n========================================\n";
print " AUDITORÍA PROFUNDA DEL DATASET ML\n";
print "========================================\n";
print "Entrada TRAIN:      $train_file\n";
print "Entrada VALIDATION: $validation_file\n";
print "TEST FINAL:         RESERVADO, NO SE LEE\n";

my $train = $auditor->read_csv($train_file);
my $validation = $auditor->read_csv($validation_file);
my $result = $auditor->audit(
    train => $train,
    validation => $validation,
    output_dir => $output_dir,
);

print "\nFilas auditadas:             $result->{rows}\n";
print "Variables numéricas:         $result->{numeric}\n";
print "Variables categóricas:       $result->{categorical}\n";
print "Grupos duplicados:           $result->{duplicates}\n";
print "Alertas de filas sospechosas: $result->{suspicious}\n";
print "\nReportes generados en:\n$output_dir\n";
print "\nAbra primero:\n$output_dir/AUDIT_REPORT.md\n";
print "========================================\n";
