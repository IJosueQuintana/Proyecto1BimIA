#!/usr/bin/env perl
use strict;use warnings;use FindBin;use lib $FindBin::Bin;
use Getopt::Long qw(GetOptions);use File::Path qw(make_path);use POSIX qw(strftime);use List::Util qw(sum);
$| = 1;
use Market::ML::FinalGhostDatasetBuilder;use Market::ML::FinalGhostFeatureSchema;use Market::ML::FinalGhostIO;use Market::ML::FinalGhostModel;use Market::ML::ModelSerializer;

my $rebuild=0;my $fast=0;my $seed=42;GetOptions('rebuild!'=>\$rebuild,'fast!'=>\$fast,'seed=i'=>\$seed) or die "Uso: perl final_ml_pipeline.pl [--rebuild] [--fast] [--seed 42]\n";
my $root=$FindBin::Bin;my $out="$root/datasets/final_ml";my $models="$root/models/final_ml";my $reports="$root/reports/final_ml";make_path($_) for grep{!-d$_}($out,$models,$reports);
my @train=map{"$root/data_final/$_"}qw(2026_04.csv 2026_05.csv 2026_06.csv);my @test=("$root/data_final/2026_07_24.csv");
my $train_csv="$out/train_ghost_features.csv";my $test_csv="$out/test_ghost_features.csv";

my($train_rows,$test_rows);
if($rebuild||!-f$train_csv||!-f$test_csv){
    print "\n[1/4] EXTRACCION CAUSAL + ETIQUETADO 3/5/10/15\n";
    my$b=Market::ML::FinalGhostDatasetBuilder->new(symbol=>'NQ',pip_size=>0.25);my(@tr,@te);
    for my$f(@train){die"Falta $f\n"if!-f$f;my$r=$b->build_file_dataset(file=>$f);push@tr,@{$r->{rows}};print "TRAIN ",$r->{source_file},": $r->{candle_count} velas -> $r->{ghost_count} fantasmas\n";}
    for my$f(@test){die"Falta $f\n"if!-f$f;my$r=$b->build_file_dataset(file=>$f);push@te,@{$r->{rows}};print "TEST  ",$r->{source_file},": $r->{candle_count} velas -> $r->{ghost_count} fantasmas\n";}
    my@cols=sort keys%{$tr[0]};Market::ML::FinalGhostIO->write_csv(file=>$train_csv,rows=>\@tr,columns=>\@cols);Market::ML::FinalGhostIO->write_csv(file=>$test_csv,rows=>\@te,columns=>\@cols);
    $train_rows=\@tr;$test_rows=\@te;
}else{print "\n[1/4] Usando datasets finales ya extraidos (use --rebuild para regenerar)\n";$train_rows=Market::ML::FinalGhostIO->read_csv(file=>$train_csv);$test_rows=Market::ML::FinalGhostIO->read_csv(file=>$test_csv);}

print "TRAIN fantasmas: ",scalar(@$train_rows)," | TEST fantasmas: ",scalar(@$test_rows),"\n";
my $iters=$fast?300:360;my $anchors=$fast?90:180;
print "\n[2/4] t-SNE -> HMM -> GMM\n";
my$model=Market::ML::FinalGhostModel->new(seed=>$seed,perplexity=>25,tsne_iterations=>$iters,max_tsne_anchors=>$anchors,projector_k=>8);
$model->fit(rows=>$train_rows);my$summary=$model->summary;print "t-SNE: anchors=$summary->{tsne_anchors} perplexity=$summary->{tsne_perplexity} KL=$summary->{tsne_kl}\n";print "HMM: states=QUIET/ACTIVE/INTENSE logL=$summary->{hmm_log_likelihood}\n";print "GMM: components=$summary->{gmm_components} BIC=$summary->{gmm_bic} converged=$summary->{gmm_converged}\n";
Market::ML::ModelSerializer->save(file=>"$models/ghost_tsne_hmm_gmm.bin",object=>$model,metadata=>{order=>'t-SNE -> HMM -> GMM',train_files=>[map{(split'/')[-1]}@train],test_file=>'2026_07_24.csv',pip_size=>0.25,ghost_definition=>'EXTERNAL_SWING_CONFIRMATION',trace_definition=>'new outward extensions of running high/low from next candle',seed=>$seed});

print "\n[3/4] EVALUACION EN JULIO 1-24\n";my$pred=$model->predict(rows=>$test_rows);my@merged;
for my$i(0..$#$test_rows){push@merged,{%{$test_rows->[$i]},%{$pred->[$i]}};}
my@predcols=sort keys%{$merged[0]};Market::ML::FinalGhostIO->write_csv(file=>"$out/test_predictions.csv",rows=>\@merged,columns=>\@predcols);
my$metrics=_metrics($test_rows,$pred);my$baseline=_baseline_metrics($train_rows,$test_rows);
_print_metrics('MODELO FINAL t-SNE -> HMM -> GMM',$metrics);_print_metrics('BASELINE MEDIA TRAIN',$baseline);

print "\n[4/4] GENERANDO REPORTE\n";_write_report("$reports/FINAL_ML_REPORT.md",$summary,$metrics,$baseline,scalar(@$train_rows),scalar(@$test_rows));
print "Modelo:      models/final_ml/ghost_tsne_hmm_gmm.bin\n";print "Predicciones: datasets/final_ml/test_predictions.csv\n";print "Reporte:      reports/final_ml/FINAL_ML_REPORT.md\n";print "\nPIPELINE FINAL COMPLETADO.\n";

sub _metrics{my($actual,$pred)=@_;my%o;for my$h(qw(3 5 10 15)){my($ae,$se,$exact,$within1)=(0,0,0,0);my$n=@$actual;for my$i(0..$#$actual){my$a=0+$actual->[$i]{"target_trace_$h"};my$p=0+$pred->[$i]{"pred_trace_$h"};$ae+=abs($a-$p);$se+=($a-$p)**2;$exact++ if int($p+0.5)==$a;$within1++ if abs(int($p+0.5)-$a)<=1;}$o{$h}={mae=>$ae/$n,rmse=>sqrt($se/$n),exact_accuracy=>$exact/$n,within1_accuracy=>$within1/$n};}return\%o;}
sub _baseline_metrics{my($train,$test)=@_;my%mean;for my$h(qw(3 5 10 15)){$mean{$h}=sum(map{0+$_->{"target_trace_$h"}}@$train)/@$train;}my@p=map{{map{("pred_trace_$_"=>$mean{$_})}qw(3 5 10 15)}}@$test;return _metrics($test,\@p);}
sub _print_metrics{my($name,$m)=@_;print"\n$name\n";printf"%-8s %-10s %-10s %-10s %-10s\n",'Horizonte','MAE','RMSE','ExactAcc','±1Acc';for my$h(qw(3 5 10 15)){printf"%-8s %-10.4f %-10.4f %-9.2f%% %-9.2f%%\n","${h}m",$m->{$h}{mae},$m->{$h}{rmse},100*$m->{$h}{exact_accuracy},100*$m->{$h}{within1_accuracy};}}
sub _write_report{my($file,$s,$m,$b,$ntr,$nte)=@_;open my$fh,'>:encoding(UTF-8)',$file or die$!;print {$fh} "# Reporte final de Machine Learning\n\n";print {$fh} "## Contrato experimental\n\n- TRAIN: abril, mayo y junio 2026 ($ntr eventos fantasma).\n- TEST: 1-24 julio 2026 ($nte eventos fantasma).\n- Orden ejecutado: **t-SNE -> HMM -> GMM**.\n- Unidad PIP configurada: **0.25**.\n- El test no participa en scaler, t-SNE, HMM, GMM ni mapeos de targets.\n\n";print {$fh} "## Definicion operacional del fantasma y rastro\n\nEl proyecto recibido no incluye el archivo fuente `Ghosts_in_swings.txt` citado por las indicaciones. Para dejar el pipeline ejecutable, el evento fantasma se operacionaliza como la **confirmacion de un swing externo** ya calculado por el motor ChartPrime/SMC del proyecto. Desde la vela siguiente se cuenta un rastro cada vez que aparece una nueva extension hacia afuera del maximo o minimo acumulado. Los conteos son acumulados a 3, 5, 10 y 15 minutos. Esta definicion es causal y auditable, pero debe sustituirse por la logica literal del indicador del docente si se incorpora ese archivo fuente.\n\n";print {$fh} "## Evidencia de las tres etapas\n\n- t-SNE: $s->{tsne_anchors} anclas, perplexity $s->{tsne_perplexity}, KL final $s->{tsne_kl}.\n- HMM: estados QUIET/ACTIVE/INTENSE, log-verosimilitud TRAIN $s->{hmm_log_likelihood}.\n- GMM: $s->{gmm_components} componentes, BIC $s->{gmm_bic}, convergencia $s->{gmm_converged}, $s->{gmm_feature_count} features seleccionadas + embedding/posteriores.\n- Features causales: $s->{feature_count}.\n\n";print {$fh} "## Metricas sobre TEST de julio\n\n| Horizonte | MAE modelo | RMSE modelo | Exactitud exacta | Exactitud ±1 | MAE baseline | Mejora MAE |\n|---|---:|---:|---:|---:|---:|---:|\n";for my$h(qw(3 5 10 15)){my $improve=$b->{$h}{mae}>0?100*($b->{$h}{mae}-$m->{$h}{mae})/$b->{$h}{mae}:0; printf {$fh} "| %s min | %.4f | %.4f | %.2f%% | %.2f%% | %.4f | %.2f%% |\n",$h,$m->{$h}{mae},$m->{$h}{rmse},100*$m->{$h}{exact_accuracy},100*$m->{$h}{within1_accuracy},$b->{$h}{mae},$improve;}print {$fh} "\n## Artefactos\n\n- `datasets/final_ml/train_ghost_features.csv`\n- `datasets/final_ml/test_ghost_features.csv`\n- `datasets/final_ml/test_predictions.csv`\n- `models/final_ml/ghost_tsne_hmm_gmm.bin`\n- `final_ml_demo.pl`\n- `verify_final_ml.pl`\n\n";close$fh;}
