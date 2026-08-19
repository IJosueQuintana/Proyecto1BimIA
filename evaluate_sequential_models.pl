#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use Getopt::Long qw(GetOptions);
use Market::ML::SequentialDatasetLoader;
use Market::ML::ModelSerializer;
use Market::ML::SequentialGMMTrainer;
use Market::ML::SequentialHMMTrainer;
use Market::ML::ClassificationMetrics;
use Market::ML::BaselineModels;

my $dataset = 'datasets/sequential_features_1m.csv';
my $gmm_file = 'models/sequential_gmm.bin';
my $hmm_file = 'models/sequential_hmm.bin';
my $seed = 42;
GetOptions(
    'dataset=s' => \$dataset,
    'gmm=s'     => \$gmm_file,
    'hmm=s'     => \$hmm_file,
    'seed=i'    => \$seed,
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
my $train_supervised = $loader->rows_for_supervised_model(
    rows => $split->{train_rows}, target_column => 'state_label'
);
my $validation_supervised = $loader->rows_for_supervised_model(
    rows => $split->{validation_rows}, target_column => 'state_label'
);

my $metrics = Market::ML::ClassificationMetrics->new(labels => \@labels);
my $baselines = Market::ML::BaselineModels->new(seed => $seed);
my ($zero_pred, $majority) = $baselines->zero_rule_predict(
    train_rows => $train_supervised,
    test_rows => $validation_supervised,
);
$metrics->print_report("ZERO RULE (majority=$majority)", $metrics->evaluate(
    actual => $actual, predicted => $zero_pred
));

my $random_pred = $baselines->random_predict(
    train_rows => $train_supervised,
    test_rows => $validation_supervised,
    seed => $seed,
);
$metrics->print_report('RANDOM PREDICTION', $metrics->evaluate(
    actual => $actual, predicted => $random_pred
));

my $gmm = Market::ML::ModelSerializer->load(file => $gmm_file);
my $gmm_pred;
if ($gmm->can('predict_labels')) {
    $gmm_pred = $gmm->predict_labels(rows => $split->{validation_rows});
}
elsif ($gmm->can('predict_clusters') && $gmm->can('cluster_map')) {
    my $clusters = $gmm->predict_clusters(rows => $split->{validation_rows});
    my $map = $gmm->cluster_map;
    $gmm_pred = [map { $map->{$_} // 'IDLE' } @$clusters];
}
else {
    die "El modelo GMM cargado no expone predict_labels ni la interfaz predict_clusters/cluster_map. Reemplaza Market/ML/SequentialGMMTrainer.pm con el hotfix.\n";
}
$metrics->print_report('SEQUENTIAL GMM', $metrics->evaluate(
    actual => $actual, predicted => $gmm_pred
));

my $hmm = Market::ML::ModelSerializer->load(file => $hmm_file);
my $validation_ids = $loader->sequence_ids(rows => $split->{validation_rows});
my $hmm_online = $hmm->predict_online(
    rows => $split->{validation_rows}, sequence_ids => $validation_ids
);
$metrics->print_report('TEMPORAL HMM - ONLINE FILTERING', $metrics->evaluate(
    actual => $actual, predicted => $hmm_online
));

my $hmm_viterbi = $hmm->viterbi(
    rows => $split->{validation_rows}, sequence_ids => $validation_ids
);
$metrics->print_report('TEMPORAL HMM - VITERBI', $metrics->evaluate(
    actual => $actual, predicted => $hmm_viterbi
));

print "\nTEST was not loaded or evaluated.\n";
