package Market::ML::DatasetVersionComparator;

use strict;
use warnings;
use File::Path qw(make_path);
use File::Spec;
use List::Util qw(sum);

use Market::ML::FeatureSchema;
use Market::ML::StandardScaler;
use Market::ML::GaussianMixtureModel;
use Market::ML::ClassificationMetrics;
use Market::ML::TSNEPipeline;

sub new {
    my ($class, %args) = @_;
    return bless {
        output_dir => $args{output_dir} // 'datasets/ml_pipeline/comparison_v1_v2',
        seed       => $args{seed} // 42,
        components => $args{components} // [2,3,4,5],
    }, $class;
}

sub run {
    my ($self, %args) = @_;
    my $v1_train = _read_csv($args{v1_train});
    my $v1_val   = _read_csv($args{v1_validation});
    my $v2_train = _read_csv($args{v2_train});
    my $v2_val   = _read_csv($args{v2_validation});

    make_path($self->{output_dir}) if !-d $self->{output_dir};

    my $v1 = $self->_evaluate_version('V1', $v1_train, $v1_val);
    my $v2 = $self->_evaluate_version('V2', $v2_train, $v2_val);

    my $tsne_v1 = File::Spec->catfile($self->{output_dir}, 'tsne_v1.csv');
    my $tsne_v2 = File::Spec->catfile($self->{output_dir}, 'tsne_v2.csv');
    my @all_v1 = (@$v1_train, @$v1_val);
    my @all_v2 = (@$v2_train, @$v2_val);

    my $pipe = Market::ML::TSNEPipeline->new(
        perplexity => 30, max_iter => 750, random_state => $self->{seed}, verbose => 0,
    );
    my $tsne1 = $pipe->run(rows => \@all_v1, output_file => $tsne_v1);
    my $tsne2 = $pipe->run(rows => \@all_v2, output_file => $tsne_v2);

    my $csv = File::Spec->catfile($self->{output_dir}, 'gmm_comparison.csv');
    _write_comparison_csv($csv, $v1, $v2);
    my $report = File::Spec->catfile($self->{output_dir}, 'COMPARISON_REPORT.md');
    _write_report($report, $v1, $v2, $tsne1, $tsne2);

    return { v1=>$v1, v2=>$v2, report=>$report, csv=>$csv, tsne_v1=>$tsne_v1, tsne_v2=>$tsne_v2 };
}

sub _evaluate_version {
    my ($self, $name, $train, $val) = @_;
    my @features = @{Market::ML::FeatureSchema->select_feature_columns(rows => $train)};
    my @results;
    my $metrics = Market::ML::ClassificationMetrics->new(labels => [qw(RUN GRAB SWEEP)]);

    for my $k (@{$self->{components}}) {
        my $scaler = Market::ML::StandardScaler->new(feature_columns => \@features);
        my $xtr = $scaler->fit_transform(rows => $train);
        my $xva = $scaler->transform(rows => $val);
        my $gmm = Market::ML::GaussianMixtureModel->new(components=>$k, seed=>$self->{seed});
        $gmm->fit(vectors=>$xtr);
        my $ctr = $gmm->predict_components(vectors=>$xtr);
        my $cva = $gmm->predict_components(vectors=>$xva);
        my $map = _map_components($ctr, $train, $k);
        my @pred = map { $map->{$_} // 'SWEEP' } @$cva;
        my @actual = map { uc($_->{target} // '') } @$val;
        my $m = $metrics->evaluate(actual=>\@actual, predicted=>\@pred);
        my @counts = (0) x $k;
        $counts[$_]++ for @$ctr;
        push @results, {
            components=>$k, accuracy=>$m->{accuracy}, macro_f1=>$m->{macro_f1},
            bic=>$gmm->bic(vectors=>$xtr), converged=>$gmm->converged,
            iterations=>$gmm->iterations, dimensions=>scalar(@{$scaler->output_features}),
            component_counts=>\@counts, mapping=>$map, metrics=>$m,
        };
    }
    my ($best) = sort { $b->{macro_f1}<=>$a->{macro_f1} || $b->{accuracy}<=>$a->{accuracy} || $a->{bic}<=>$b->{bic} || $a->{components}<=>$b->{components} } @results;
    return { name=>$name, train_rows=>scalar(@$train), validation_rows=>scalar(@$val), feature_count=>scalar(@features), results=>\@results, best=>$best };
}

sub _map_components {
    my ($components, $rows, $k) = @_;
    my %count;
    for my $i (0..$#$components) { $count{$components->[$i]}{uc($rows->[$i]{target}//'')}++; }
    my %map;
    for my $c (0..$k-1) {
        my @labels = sort { ($count{$c}{$b}//0) <=> ($count{$c}{$a}//0) || $a cmp $b } qw(RUN GRAB SWEEP);
        $map{$c} = $labels[0] // 'SWEEP';
    }
    return \%map;
}

sub _write_comparison_csv {
    my ($file, @versions) = @_;
    open my $fh, '>:encoding(UTF-8)', $file or die "No se puede escribir $file: $!\n";
    print $fh "version,components,dimensions,accuracy,macro_f1,bic,converged,iterations,component_counts,mapping\n";
    for my $v (@versions) {
        for my $r (@{$v->{results}}) {
            my $counts = join('|', @{$r->{component_counts}});
            my $map = join('|', map { $_.'='.$r->{mapping}{$_} } sort {$a<=>$b} keys %{$r->{mapping}});
            print $fh join(',', $v->{name}, $r->{components}, $r->{dimensions}, sprintf('%.6f',$r->{accuracy}), sprintf('%.6f',$r->{macro_f1}), sprintf('%.4f',$r->{bic}), $r->{converged}?1:0, $r->{iterations}, $counts, $map), "\n";
        }
    }
    close $fh;
}

sub _write_report {
    my ($file, $v1, $v2, $t1, $t2) = @_;
    open my $fh, '>:encoding(UTF-8)', $file or die "No se puede escribir $file: $!\n";
    print $fh "# Comparación Dataset V1 vs V2\n\n**TEST permanece reservado y no se lee.**\n\n";
    for my $v ($v1,$v2) {
        print $fh "## $v->{name}\n\n- TRAIN: **$v->{train_rows}**\n- VALIDATION: **$v->{validation_rows}**\n- Features originales: **$v->{feature_count}**\n\n";
        print $fh "| Componentes | Dimensiones | Accuracy | Macro-F1 | BIC | Distribución TRAIN |\n|---:|---:|---:|---:|---:|---|\n";
        for my $r (@{$v->{results}}) {
            print $fh sprintf("| %d | %d | %.4f | %.4f | %.2f | %s |\n", $r->{components},$r->{dimensions},$r->{accuracy},$r->{macro_f1},$r->{bic},join(' / ',@{$r->{component_counts}}));
        }
        my $b=$v->{best};
        print $fh sprintf("\n**Mejor configuración:** %d componentes, accuracy %.4f, Macro-F1 %.4f.\n\n",$b->{components},$b->{accuracy},$b->{macro_f1});
    }
    my $delta_f1=$v2->{best}{macro_f1}-$v1->{best}{macro_f1};
    my $delta_acc=$v2->{best}{accuracy}-$v1->{best}{accuracy};
    print $fh "## Comparación final\n\n";
    print $fh sprintf("- Cambio Macro-F1 V2 - V1: **%+.4f**\n- Cambio accuracy V2 - V1: **%+.4f**\n",$delta_f1,$delta_acc);
    print $fh "- t-SNE V1: `$t1->{output_file}` ($t1->{tensor_dimensions} dimensiones, KL=".sprintf('%.6f',$t1->{kl_divergence}//0).")\n";
    print $fh "- t-SNE V2: `$t2->{output_file}` ($t2->{tensor_dimensions} dimensiones, KL=".sprintf('%.6f',$t2->{kl_divergence}//0).")\n\n";
    print $fh "## Criterio\n\nV2 se considera superior si mejora Macro-F1 o si mantiene métricas similares con componentes menos colapsados y mucha menor dimensionalidad. Si ambos datasets siguen mapeando casi todo a SWEEP, la evidencia apunta a que el problema principal está en la definición de las observaciones y etiquetas, no solo en la selección de features.\n";
    close $fh;
}

sub _read_csv {
    my ($file)=@_; die "No existe $file\n" if !-f $file;
    open my $fh,'<:encoding(UTF-8)',$file or die "No se puede abrir $file: $!\n";
    my $h=<$fh>; chomp $h; $h=~s/\r$//; my @headers=_parse($h); my @rows;
    while(my $l=<$fh>){ chomp$l; $l=~s/\r$//; next if $l eq ''; my @v=_parse($l); push @v,('')x(@headers-@v) if @v<@headers; $#v=$#headers if @v>@headers; my %r; @r{@headers}=@v; push @rows,\%r; }
    close $fh; return \@rows;
}
sub _parse { my($l)=@_; my(@f,$x);$x='';my$q=0;my@c=split//,$l;for(my$i=0;$i<@c;$i++){my$z=$c[$i];if($q){if($z eq '"'){if($i+1<@c&&$c[$i+1] eq '"'){$x.='"';$i++}else{$q=0}}else{$x.=$z}}else{if($z eq '"'){$q=1}elsif($z eq ','){push@f,$x;$x=''}else{$x.=$z}}}push@f,$x;return@f;}
1;
