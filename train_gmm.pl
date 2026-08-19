#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use Getopt::Long qw(GetOptions);
use Market::ML::SequentialDatasetLoader;
use Market::ML::SequentialGMMTrainer;
use Market::ML::ModelSerializer;

my $dataset = 'datasets/sequential_features_1m.csv';
my $out = 'models/sequential_gmm.bin';
my $components = 4;
my $iterations = 100;
my $seed = 42;
GetOptions(
    'dataset=s'    => \$dataset,
    'out=s'        => \$out,
    'components=i' => \$components,
    'iterations=i' => \$iterations,
    'seed=i'       => \$seed,
) or die "Opciones inválidas\n";

my @train_files = qw(2026_03.csv 2026_06_29.csv 2026_07_06.csv);
my @validation_files = qw(2026_07_13.csv);
my $loader = Market::ML::SequentialDatasetLoader->new;
my $rows = $loader->load_csv(file => $dataset);
my $split = $loader->split_by_source(
    rows => $rows,
    train_files => \@train_files,
    validation_files => \@validation_files,
);

my $trainer = Market::ML::SequentialGMMTrainer->new(
    components => $components,
    max_iterations => $iterations,
    seed => $seed,
);
$trainer->fit(rows => $split->{train_rows});
my $summary = $trainer->summary;
Market::ML::ModelSerializer->save(
    file => $out,
    object => $trainer,
    metadata => {
        dataset => $dataset,
        train_files => \@train_files,
        validation_files => \@validation_files,
        target => 'state_label',
    },
);

print "GMM TRAINED\n";
print "TRAIN rows: ", scalar(@{$split->{train_rows}}), "\n";
print "VALIDATION reserved: ", scalar(@{$split->{validation_rows}}), "\n";
print "Components: $summary->{components}\n";
print "Converged: ", ($summary->{converged} ? 'yes' : 'no'), "\n";
print "Iterations: $summary->{iterations}\n";
print "Log-likelihood: $summary->{log_likelihood}\n";
print "Cluster map: ", join(', ', map { "$_=$summary->{cluster_map}{$_}" } sort {$a<=>$b} keys %{$summary->{cluster_map}}), "\n";
print "Saved: $out\n";
