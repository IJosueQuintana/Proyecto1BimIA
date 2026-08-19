#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use Getopt::Long qw(GetOptions);
use Market::ML::SequentialDatasetLoader;
use Market::ML::SequentialHMMTrainer;
use Market::ML::HMMStateCalibrator;
use Market::ML::ModelSerializer;
use Market::ML::ClassificationMetrics;

my $dataset = 'datasets/sequential_features_1m.csv';
my $hmm_file = 'models/sequential_hmm.bin';
my $calibration_file = 'models/hmm_state_calibration.bin';
GetOptions(
    'dataset=s'     => \$dataset,
    'hmm=s'         => \$hmm_file,
    'calibration=s' => \$calibration_file,
) or die "Opciones inválidas\n";

my @train_files = qw(2026_03.csv 2026_06_29.csv 2026_07_06.csv);
my @validation_files = qw(2026_07_13.csv);
my @labels = qw(IDLE APPROACH INTERACTION EXPANSION);
my $loader = Market::ML::SequentialDatasetLoader->new;
my $rows = $loader->load_csv(file => $dataset);
my $split = $loader->split_by_source(
    rows => $rows,
    train_files => \@train_files,
    validation_files => \@validation_files,
);
my $actual = $loader->labels(rows => $split->{validation_rows}, column => 'state_label');
my $ids = $loader->sequence_ids(rows => $split->{validation_rows});
my $hmm = Market::ML::ModelSerializer->load(file => $hmm_file);
my $calibrator = Market::ML::ModelSerializer->load(file => $calibration_file);
my ($raw, $posteriors) = $hmm->predict_online(rows => $split->{validation_rows}, sequence_ids => $ids);
my $calibrated = $calibrator->apply(posteriors => $posteriors, sequence_ids => $ids);
my $metrics = Market::ML::ClassificationMetrics->new(labels => \@labels);
$metrics->print_report('HMM ONLINE - RAW', $metrics->evaluate(actual => $actual, predicted => $raw));
$metrics->print_report('HMM ONLINE - CALIBRATED', $metrics->evaluate(actual => $actual, predicted => $calibrated));
my $config = $calibrator->config;
printf "Calibration: expansion_threshold=%.2f, require_interaction=%s\n",
    $config->{expansion_threshold}, $config->{require_interaction} ? 'yes' : 'no';
print "TEST was not loaded or evaluated.\n";
