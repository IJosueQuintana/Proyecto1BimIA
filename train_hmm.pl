#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use Getopt::Long qw(GetOptions);
use Market::ML::SequentialDatasetLoader;
use Market::ML::SequentialHMMTrainer;
use Market::ML::ModelSerializer;

my $dataset = 'datasets/sequential_features_1m.csv';
my $out = 'models/sequential_hmm.bin';
my $smoothing = 1.0;
my $variance_floor = 1e-2;
GetOptions(
    'dataset=s'        => \$dataset,
    'out=s'            => \$out,
    'smoothing=f'      => \$smoothing,
    'variance-floor=f' => \$variance_floor,
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
my $sequence_ids = $loader->sequence_ids(rows => $split->{train_rows});

my $trainer = Market::ML::SequentialHMMTrainer->new(
    smoothing => $smoothing,
    variance_floor => $variance_floor,
);
$trainer->fit(rows => $split->{train_rows}, sequence_ids => $sequence_ids);
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

print "HMM TRAINED\n";
print "TRAIN rows: ", scalar(@{$split->{train_rows}}), "\n";
print "VALIDATION reserved: ", scalar(@{$split->{validation_rows}}), "\n";
print "States: ", join(', ', @{$summary->{states}}), "\n";
print "Dimensions: $summary->{dimensions}\n";
print "Train log-likelihood: $summary->{train_log_likelihood}\n";
print "Saved: $out\n";
