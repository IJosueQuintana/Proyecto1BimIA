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
my $out_file = 'models/hmm_state_calibration.bin';
GetOptions(
    'dataset=s' => \$dataset,
    'hmm=s'     => \$hmm_file,
    'out=s'     => \$out_file,
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
my ($raw_pred, $posteriors) = $hmm->predict_online(
    rows => $split->{validation_rows},
    sequence_ids => $ids,
);

my $metrics = Market::ML::ClassificationMetrics->new(labels => \@labels);
$metrics->print_report('HMM ONLINE - RAW VALIDATION', $metrics->evaluate(
    actual => $actual, predicted => $raw_pred,
));

my $calibrator = Market::ML::HMMStateCalibrator->new;
my $search = $calibrator->fit(
    actual => $actual,
    posteriors => $posteriors,
    sequence_ids => $ids,
);
my $calibrated = $calibrator->apply(posteriors => $posteriors, sequence_ids => $ids);
$metrics->print_report('HMM ONLINE - CALIBRATED VALIDATION', $metrics->evaluate(
    actual => $actual, predicted => $calibrated,
));

my $config = $calibrator->config;
printf "Selected expansion threshold: %.2f\n", $config->{expansion_threshold};
print "Require previous INTERACTION: ", ($config->{require_interaction} ? 'yes' : 'no'), "\n";
print "Configurations evaluated: $config->{validation_summary}{trials}\n";

Market::ML::ModelSerializer->save(
    file => $out_file,
    object => $calibrator,
    metadata => {
        selected_on => 'VALIDATION only',
        test_used => 0,
        validation_files => \@validation_files,
    },
);
print "Saved: $out_file\n";
print "TEST was not loaded or evaluated.\n";
