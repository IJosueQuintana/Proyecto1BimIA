#!/usr/bin/env perl
use strict;use warnings;use FindBin;use lib $FindBin::Bin;use Getopt::Long qw(GetOptions);
use Market::ML::FinalGhostIO;use Market::ML::FinalGhostModel;use Market::ML::ModelSerializer;
my$n=12;GetOptions('n=i'=>\$n)or die"Uso: perl final_ml_demo.pl [--n 12]\n";
my$rows=Market::ML::FinalGhostIO->read_csv(file=>"$FindBin::Bin/datasets/final_ml/test_ghost_features.csv");my($model,$meta)=Market::ML::ModelSerializer->load(file=>"$FindBin::Bin/models/final_ml/ghost_tsne_hmm_gmm.bin");my$p=$model->predict(rows=>$rows);
print"\nDEMO MODELO CARGADO: $meta->{order}\n";print"TEST: $meta->{test_file} | ghost=$meta->{ghost_definition}\n\n";printf"%-20s %-7s %-7s %-7s %-7s %-9s %-7s\n",'timestamp','3m','5m','10m','15m','HMM','GMM';
for my$i(0..$#$rows){last if$i>=$n;printf"%-20s %d/%-4d %d/%-4d %d/%-4d %d/%-4d %-9s %-7d\n",substr($rows->[$i]{ghost_timestamp}//'',0,19),$p->[$i]{pred_trace_3_rounded},$rows->[$i]{target_trace_3},$p->[$i]{pred_trace_5_rounded},$rows->[$i]{target_trace_5},$p->[$i]{pred_trace_10_rounded},$rows->[$i]{target_trace_10},$p->[$i]{pred_trace_15_rounded},$rows->[$i]{target_trace_15},$p->[$i]{hmm_state},$p->[$i]{gmm_cluster};}
print"\nFormato: predicho/real. Las predicciones provienen de un modelo cargado desde disco.\n";
