#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use lib "$FindBin::Bin/Market";
use File::Spec;
use Market::ML::DatasetV2Builder;

my $root=$FindBin::Bin;
my $input=File::Spec->catdir($root,'datasets','ml_pipeline');
my $output=File::Spec->catdir($input,'v2');
my $train=File::Spec->catfile($input,'train_trainable.csv');
my $validation=File::Spec->catfile($input,'validation_trainable.csv');

print "\n========================================\n CAMBIO 06A - DATASET DE PIVOTES V2\n========================================\n";
print "TRAIN:      $train\nVALIDATION: $validation\nTEST FINAL: RESERVADO, NO SE LEE\n\n";
my $builder=Market::ML::DatasetV2Builder->new(output_dir=>$output);
my $r=$builder->build(train_file=>$train,validation_file=>$validation);
print "TRAIN original:         $r->{train_rows_original}\nTRAIN V2:               $r->{train_rows_v2}\nVALIDATION V2:          $r->{validation_rows}\nDuplicados eliminados:  $r->{duplicates_removed}\nFeatures numéricas:     $r->{numeric_count}\nFeatures categóricas:   $r->{categorical_count}\nPredictores totales V2: $r->{predictor_count}\n\n";
print "Archivos generados:\n  $r->{train_out}\n  $r->{validation_out}\n  $r->{report_file}\n  $r->{features_file}\n  $r->{duplicates_file}\n\n";
print "IMPORTANTE:\n  - No se modificaron los CSV originales.\n  - No se leyó TEST.\n  - RUN/GRAB/SWEEP permanecen intactos.\n========================================\n";
