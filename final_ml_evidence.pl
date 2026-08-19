#!/usr/bin/env perl
use strict;use warnings;use FindBin;use lib $FindBin::Bin;
use List::Util qw(min max);
use Market::ML::FinalGhostIO;use Market::ML::FinalGhostModel;use Market::ML::ModelSerializer;

my $train=Market::ML::FinalGhostIO->read_csv(file=>"$FindBin::Bin/datasets/final_ml/train_ghost_features.csv");
my $test=Market::ML::FinalGhostIO->read_csv(file=>"$FindBin::Bin/datasets/final_ml/test_ghost_features.csv");
my($model,$meta)=Market::ML::ModelSerializer->load(file=>"$FindBin::Bin/models/final_ml/ghost_tsne_hmm_gmm.bin");
my $p_train=$model->predict(rows=>$train);my $p_test=$model->predict(rows=>$test);my $summary=$model->summary;

my @embedding;
for my $set ([TRAIN=>$train=>$p_train],[TEST=>$test=>$p_test]) {
    my($split,$rows,$pred)=@$set;
    for my$i(0..$#$rows){push@embedding,{split=>$split,ghost_timestamp=>$rows->[$i]{ghost_timestamp},source_file=>$rows->[$i]{source_file},target_trace_15=>$rows->[$i]{target_trace_15},tsne_x=>$pred->[$i]{tsne_x},tsne_y=>$pred->[$i]{tsne_y},hmm_state=>$pred->[$i]{hmm_state},gmm_cluster=>$pred->[$i]{gmm_cluster}};}
}
Market::ML::FinalGhostIO->write_csv(file=>"$FindBin::Bin/datasets/final_ml/tsne_hmm_gmm_embedding.csv",rows=>\@embedding,columns=>[qw(split ghost_timestamp source_file target_trace_15 tsne_x tsne_y hmm_state gmm_cluster)]);

_write_svg("$FindBin::Bin/reports/final_ml/tsne_hmm_gmm.svg",\@embedding);
_write_evidence("$FindBin::Bin/reports/final_ml/MODEL_EVIDENCE.txt",$model,$meta,$summary,scalar(@$train),scalar(@$test));
print "Generated:\n  datasets/final_ml/tsne_hmm_gmm_embedding.csv\n  reports/final_ml/tsne_hmm_gmm.svg\n  reports/final_ml/MODEL_EVIDENCE.txt\n";

sub _write_svg{
    my($file,$rows)=@_;my@x=map{0+$_->{tsne_x}}@$rows;my@y=map{0+$_->{tsne_y}}@$rows;my($xmin,$xmax)=(min(@x),max(@x));my($ymin,$ymax)=(min(@y),max(@y));$xmax=$xmin+1 if$xmax==$xmin;$ymax=$ymin+1 if$ymax==$ymin;
    my($w,$h,$pad)=(1100,720,70);my%color=(QUIET=>'#3b82f6',ACTIVE=>'#f59e0b',INTENSE=>'#ef4444');
    open my$fh,'>:encoding(UTF-8)',$file or die$!;print {$fh} qq{<svg xmlns="http://www.w3.org/2000/svg" width="$w" height="$h" viewBox="0 0 $w $h">\n<rect width="100%" height="100%" fill="#0b1220"/>\n};
    print {$fh} qq{<text x="$pad" y="38" fill="#f8fafc" font-family="Arial" font-size="24" font-weight="700">t-SNE → HMM → GMM — evidencia del modelo final</text>\n};
    print {$fh} qq{<text x="$pad" y="62" fill="#94a3b8" font-family="Arial" font-size="14">Color = estado HMM · círculo = TRAIN · rombo = TEST · cluster GMM disponible en CSV</text>\n};
    print {$fh} qq{<rect x="$pad" y="80" width="}.($w-2*$pad).qq{" height="}.($h-150).qq{" fill="#111827" stroke="#334155"/>\n};
    for my$r(@$rows){my$x=$pad+(($r->{tsne_x}-$xmin)/($xmax-$xmin))*($w-2*$pad);my$y=80+(1-(($r->{tsne_y}-$ymin)/($ymax-$ymin)))*($h-150);my$c=$color{$r->{hmm_state}}//'#e2e8f0';if($r->{split} eq 'TEST'){my$s=4;print {$fh} qq{<polygon points="}.($x).qq{,}.($y-$s).qq{ }.($x+$s).qq{,$y $x,}.($y+$s).qq{ }.($x-$s).qq{,$y" fill="$c" stroke="#ffffff" stroke-width="0.7" opacity="0.85"/>\n};}else{print {$fh} qq{<circle cx="$x" cy="$y" r="2.4" fill="$c" opacity="0.55"/>\n};}}
    my$x0=$w-355;my$yy=34;for my$s(qw(QUIET ACTIVE INTENSE)){my$c=$color{$s};print {$fh} qq{<circle cx="$x0" cy="$yy" r="5" fill="$c"/><text x="}.($x0+10).qq{" y="}.($yy+5).qq{" fill="#e2e8f0" font-family="Arial" font-size="13">$s</text>\n};$x0+=95;}
    print {$fh} qq{<text x="}.($w/2-35).qq{" y="}.($h-20).qq{" fill="#cbd5e1" font-family="Arial" font-size="14">t-SNE X</text>\n<text transform="translate(20 }.($h/2+35).qq{) rotate(-90)" fill="#cbd5e1" font-family="Arial" font-size="14">t-SNE Y</text>\n</svg>\n};close$fh;
}

sub _write_evidence{
    my($file,$model,$meta,$s,$ntr,$nte)=@_;open my$fh,'>:encoding(UTF-8)',$file or die$!;print {$fh} "FINAL ML MODEL EVIDENCE\n=======================\n";print {$fh} "Order: $meta->{order}\nTrain events: $ntr\nTest events: $nte\nFeatures causal scaler: $s->{feature_count}\nt-SNE anchors: $s->{tsne_anchors}\nt-SNE perplexity: $s->{tsne_perplexity}\nt-SNE KL: $s->{tsne_kl}\nHMM log-likelihood: $s->{hmm_log_likelihood}\nGMM components: $s->{gmm_components}\nGMM BIC: $s->{gmm_bic}\nGMM converged: $s->{gmm_converged}\nGMM selected features: $s->{gmm_feature_count}\n\nHMM transition matrix\n";
    my$t=$model->{hmm}->transition_matrix;for my$from(qw(QUIET ACTIVE INTENSE)){print {$fh} "$from -> ",join(', ',map{sprintf('%s=%.4f',$_,$t->{$from}{$_}//0)}qw(QUIET ACTIVE INTENSE)),"\n";}
    print {$fh} "\nGMM weights\n";my$weights=$model->{gmm}->weights;for my$i(0..$#$weights){printf {$fh}"cluster_%d=%.6f\n",$i,$weights->[$i];}close$fh;
}
