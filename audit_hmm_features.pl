#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use Getopt::Long qw(GetOptions);
use Market::ML::SequentialDatasetLoader;
use Market::ML::SequentialLeakageAuditor;

my $dataset = 'datasets/sequential_features_1m.csv';
GetOptions('dataset=s' => \$dataset) or die "Opciones inválidas\n";

my $loader = Market::ML::SequentialDatasetLoader->new;
my $rows = $loader->load_csv(file => $dataset);
my $auditor = Market::ML::SequentialLeakageAuditor->new;
my $report = $auditor->audit(rows => $rows);
$auditor->print_report($report);
die "AUDIT FAILED: existen etiquetas/targets dentro de X\n" if @{$report->{forbidden_in_x}};
die "AUDIT FAILED: existen features no finitas\n" if @{$report->{non_finite}};
print "AUDIT PASSED\n";
