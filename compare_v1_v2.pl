#!/usr/bin/env perl
use strict; use warnings; use FindBin; use lib $FindBin::Bin; use lib "$FindBin::Bin/Market"; use File::Spec;
use Market::ML::DatasetVersionComparator;
my $root=$FindBin::Bin; my $d=File::Spec->catdir($root,'datasets','ml_pipeline');
my $cmp=Market::ML::DatasetVersionComparator->new(output_dir=>File::Spec->catdir($d,'comparison_v1_v2'),seed=>42);
print "\n========================================\n COMPARACIÓN DATASET V1 VS V2\n========================================\nTEST FINAL: RESERVADO, NO SE LEE\n";
my $r=$cmp->run(
 v1_train=>File::Spec->catfile($d,'train_trainable.csv'),
 v1_validation=>File::Spec->catfile($d,'validation_trainable.csv'),
 v2_train=>File::Spec->catfile($d,'v2','train_v2.csv'),
 v2_validation=>File::Spec->catfile($d,'v2','validation_v2.csv'),
);
for my $v ($r->{v1},$r->{v2}){my$b=$v->{best};printf "%s: componentes=%d dimensiones=%d accuracy=%.4f macro_f1=%.4f distribución=%s\n",$v->{name},$b->{components},$b->{dimensions},$b->{accuracy},$b->{macro_f1},join('/',@{$b->{component_counts}});}
printf "Cambio V2-V1: accuracy=%+.4f macro_f1=%+.4f\n",$r->{v2}{best}{accuracy}-$r->{v1}{best}{accuracy},$r->{v2}{best}{macro_f1}-$r->{v1}{best}{macro_f1};
print "\nReportes en: ".File::Spec->catdir($d,'comparison_v1_v2')."\nAbra primero: $r->{report}\n========================================\n";
