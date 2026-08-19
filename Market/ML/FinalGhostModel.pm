package Market::ML::FinalGhostModel;

use strict;
use warnings;
use Carp qw(croak);
use List::Util qw(sum min max);

use Market::ML::FinalGhostFeatureSchema;
use Market::ML::StandardScaler;
use Market::ML::TSNE;
use Market::ML::HiddenMarkovModel;
use Market::ML::GaussianMixtureModel;

sub new {
    my ($class,%args)=@_;
    return bless {
        seed=>$args{seed}//42,
        perplexity=>$args{perplexity}//25,
        tsne_iterations=>$args{tsne_iterations}//300,
        max_tsne_anchors=>$args{max_tsne_anchors}//280,
        projector_k=>$args{projector_k}//8,
        blend_gmm=>defined($args{blend_gmm})?0+$args{blend_gmm}:0.85,
        fitted=>0,
    },$class;
}

sub fit {
    my ($self,%args)=@_; my $rows=$args{rows}//[];
    croak "rows de entrenamiento vacio\n" if ref($rows) ne 'ARRAY'||!@$rows;
    my $features=Market::ML::FinalGhostFeatureSchema->select_feature_columns(rows=>$rows);
    my $scaler=Market::ML::StandardScaler->new(feature_columns=>$features);
    my $vectors=$scaler->fit_transform(rows=>$rows);

    my $anchor_idx=_even_indices(scalar(@$vectors),$self->{max_tsne_anchors});
    my @anchor_vectors=map{$vectors->[$_]}@$anchor_idx;
    my $perp=min($self->{perplexity},int((@anchor_vectors-1)/3));$perp=2 if $perp<2;
    my $tsne=Market::ML::TSNE->new(n_components=>2,perplexity=>$perp,random_state=>$self->{seed},max_iter=>$self->{tsne_iterations},verbose=>1);
    my $anchor_coords=$tsne->fit_transform(\@anchor_vectors);
    my $coords=_project_vectors($vectors,\@anchor_vectors,$anchor_coords,$self->{projector_k});

    my $thresholds=_target_thresholds($rows);
    my @labels=map{_state_for($_->{target_trace_15},$thresholds)}@$rows;
    my @seq=map{$_->{source_file}//'TRAIN'}@$rows;
    my $hmm=Market::ML::HiddenMarkovModel->new(states=>[qw(QUIET ACTIVE INTENSE)],smoothing=>0.5,variance_floor=>1e-2);
    $hmm->fit(vectors=>$coords,labels=>\@labels,sequence_ids=>\@seq);
    my ($hmm_pred,$post)=$hmm->predict_online(vectors=>$coords,sequence_ids=>\@seq);
    my $state_means=_means_by_label($rows,\@labels);

    my @gmm_feature_columns = grep { exists $rows->[0]{$_} } qw(
        range_atr_ratio tf_1_volume_ratio_ema9 body_atr_ratio volume_ratio_20 volume_zscore_20
        candle_direction tf_60_volume_ratio_ema9 active_ssl_count pivot_body sr_weekly_resistance_pips
        tf_10_channel_lower_touches tf_60_channel_lower_touches tf_60_volume_ema9 equal_levels_previous_100
        tf_60_channel_upper_touches close_position pivot_range near_equal_level sr_daily_resistance_pips
        last_structure_event sr_weekly_support_pips tf_1_channel_lower_touches bars_since_ob
        active_fvg_count_50 active_bsl_count tf_1_channel_upper_touches bars_since_structure_event
        price_to_confirm_close ob_invalidated tf_10_volume_ratio_ema9 tf_10_atr_pips
        tf_60_atr_pips tf_1_atr_pips distance_nearest_bsl_pips distance_nearest_ssl_pips
        distance_fvg_pips distance_ob_pips liquidity_imbalance_100 swing_size_atr
    );
    my $gmm_scaler=Market::ML::StandardScaler->new(feature_columns=>\@gmm_feature_columns);
    my $gmm_vectors=$gmm_scaler->fit_transform(rows=>$rows);
    my @aug;
    for my $i (0..$#$coords) {
        push @aug, [@{$coords->[$i]}, map {0+($post->[$i]{$_}//0)} qw(QUIET ACTIVE INTENSE), @{$gmm_vectors->[$i]}];
    }
    my ($best_gmm,$best_bic);
    for my $k (7,9,12) {
        next if @aug < $k;
        my $g=Market::ML::GaussianMixtureModel->new(components=>$k,seed=>$self->{seed},max_iterations=>90,tolerance=>1e-5,regularization=>1e-2);
        $g->fit(vectors=>\@aug); my $bic=$g->bic(vectors=>\@aug);
        if(!defined($best_bic)||$bic<$best_bic){$best_bic=$bic;$best_gmm=$g;}
    }
    my $clusters=$best_gmm->predict_components(vectors=>\@aug);
    my $responsibilities=$best_gmm->predict_proba(vectors=>\@aug);
    my $cluster_means=_means_by_responsibility($rows,$responsibilities,$best_gmm->components);

    $self->{feature_columns}=$features;$self->{scaler}=$scaler;
    $self->{anchor_vectors}=\@anchor_vectors;$self->{anchor_coords}=$anchor_coords;
    $self->{tsne_perplexity_effective}=$perp;$self->{tsne_kl}=$tsne->{kl_divergence_};
    $self->{thresholds}=$thresholds;$self->{hmm}=$hmm;$self->{state_means}=$state_means;
    $self->{gmm}=$best_gmm;$self->{gmm_bic}=$best_bic;$self->{cluster_means}=$cluster_means;$self->{gmm_scaler}=$gmm_scaler;$self->{gmm_feature_columns}=\@gmm_feature_columns;
    $self->{fitted}=1;
    return $self;
}

sub predict {
    my ($self,%args)=@_; _req($self); my $rows=$args{rows}//[]; return [] if !@$rows;
    my $vectors=$self->{scaler}->transform(rows=>$rows);
    my $coords=_project_vectors($vectors,$self->{anchor_vectors},$self->{anchor_coords},$self->{projector_k});
    my @seq=map{$_->{source_file}//'TEST'}@$rows;
    my ($states,$post)=$self->{hmm}->predict_online(vectors=>$coords,sequence_ids=>\@seq);
    my $gmm_vectors=$self->{gmm_scaler}->transform(rows=>$rows);
    my @aug; for my $i(0..$#$coords){push@aug,[@{$coords->[$i]},map{0+($post->[$i]{$_}//0)}qw(QUIET ACTIVE INTENSE),@{$gmm_vectors->[$i]}];}
    my $clusters=$self->{gmm}->predict_components(vectors=>\@aug);
    my $responsibilities=$self->{gmm}->predict_proba(vectors=>\@aug);
    my @pred;
    my $wg=$self->{blend_gmm}; my $wh=1-$wg;
    for my $i(0..$#$rows){
        my %h; for my $h(qw(3 5 10 15)){
            my $hv=0; for my $s(qw(QUIET ACTIVE INTENSE)){$hv+=($post->[$i]{$s}//0)*($self->{state_means}{$s}{$h}//0);}
            my $gv=0;
            for my $c (0..$self->{gmm}->components-1) {
                $gv += ($responsibilities->[$i][$c]//0) * ($self->{cluster_means}{$c}{$h}//0);
            }
            $gv=$hv if $gv<=0;
            my $v=$wg*$gv+$wh*$hv; $v=0 if $v<0;
            $h{"pred_trace_$h"}=$v;
            $h{"pred_trace_${h}_rounded"}=int($v+0.5);
        }
        push @pred,{%h,tsne_x=>$coords->[$i][0],tsne_y=>$coords->[$i][1],hmm_state=>$states->[$i],gmm_cluster=>$clusters->[$i],
            hmm_quiet_prob=>$post->[$i]{QUIET}//0,hmm_active_prob=>$post->[$i]{ACTIVE}//0,hmm_intense_prob=>$post->[$i]{INTENSE}//0};
    }
    return \@pred;
}

sub summary {
    my($self)=@_;_req($self);return{
        order=>'t-SNE -> HMM -> GMM',feature_count=>scalar(@{$self->{feature_columns}}),
        tsne_anchors=>scalar(@{$self->{anchor_vectors}}),tsne_perplexity=>$self->{tsne_perplexity_effective},tsne_iterations=>$self->{tsne_iterations},tsne_kl=>$self->{tsne_kl},
        hmm_states=>[qw(QUIET ACTIVE INTENSE)],hmm_log_likelihood=>$self->{hmm}->train_log_likelihood,
        gmm_components=>$self->{gmm}->components,gmm_bic=>$self->{gmm_bic},gmm_converged=>$self->{gmm}->converged,gmm_iterations=>$self->{gmm}->iterations,gmm_feature_count=>scalar(@{$self->{gmm_feature_columns}//[]}),
        thresholds=>$self->{thresholds},feature_columns=>$self->{feature_columns},
    };
}

sub train_log_likelihood { return $_[0]{train_log_likelihood}; }

sub _target_thresholds { my($rows)=@_;my@v=sort{$a<=>$b}map{0+($_->{target_trace_15}//0)}@$rows;return{q1=>$v[int(0.33*$#v)],q2=>$v[int(0.66*$#v)]}; }
sub _state_for { my($v,$t)=@_;$v=0+$v;return 'QUIET' if $v<=$t->{q1};return 'ACTIVE' if $v<=$t->{q2};return 'INTENSE'; }
sub _means_by_label { my($rows,$labels)=@_;my(%s,%n);for my$i(0..$#$rows){my$l=$labels->[$i];$n{$l}++;$s{$l}{$_}+=0+($rows->[$i]{"target_trace_$_"}//0) for qw(3 5 10 15);}for my$l(qw(QUIET ACTIVE INTENSE)){my$n=$n{$l}||1;$s{$l}{$_}/=$n for qw(3 5 10 15);}return\%s; }
sub _means_by_responsibility { my($rows,$resp,$k)=@_;my(%s,%w);for my$i(0..$#$rows){for my$c(0..$k-1){my$r=0+($resp->[$i][$c]//0);$w{$c}+=$r;$s{$c}{$_}+=$r*(0+($rows->[$i]{"target_trace_$_"}//0)) for qw(3 5 10 15);}}for my$c(0..$k-1){my$w=$w{$c}||1;$s{$c}{$_}/=$w for qw(3 5 10 15);}return\%s; }
sub _means_by_cluster { my($rows,$cl,$k)=@_;my(%s,%n);for my$i(0..$#$rows){my$c=$cl->[$i];$n{$c}++;$s{$c}{$_}+=0+($rows->[$i]{"target_trace_$_"}//0) for qw(3 5 10 15);}for my$c(0..$k-1){my$n=$n{$c}||1;$s{$c}{$_}/=$n for qw(3 5 10 15);}return\%s; }

sub _even_indices { my($n,$maxn)=@_;return[0..$n-1] if $n<=$maxn;my@i;for my$k(0..$maxn-1){push@i,int($k*($n-1)/($maxn-1)+0.5);}my%u;@i=grep{!$u{$_}++}@i;return\@i; }
sub _project_vectors {
    my($vectors,$anchors,$coords,$k)=@_;my@out;
    for my$v(@$vectors){
        my@d;for my$i(0..$#$anchors){my$dist=0;for my$j(0..$#$v){my$x=$v->[$j]-$anchors->[$i][$j];$dist+=$x*$x;}push@d,[$dist,$i];}
        @d=sort{$a->[0]<=>$b->[0]}@d;
        if($d[0][0]<1e-16){push@out,[@{$coords->[$d[0][1]]}];next;}
        my($sx,$sy,$sw)=(0,0,0);my$limit=min($k,scalar@d);
        for my$r(0..$limit-1){my($dist,$idx)=@{$d[$r]};my$w=1/(sqrt($dist)+1e-9);$sx+=$w*$coords->[$idx][0];$sy+=$w*$coords->[$idx][1];$sw+=$w;}
        push@out,[$sx/$sw,$sy/$sw];
    }return\@out;
}
sub _req { croak "FinalGhostModel no entrenado\n" if !$_[0]{fitted}; }
1;
