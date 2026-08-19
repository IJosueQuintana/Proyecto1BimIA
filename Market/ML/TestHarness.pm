package Market::ML::TestHarness;

use strict;
use warnings;
use List::Util qw(sum max);

use Market::ML::BaselineModels;
use Market::ML::ClassificationMetrics;
use Market::ML::DecisionTreeClassifier;
use Market::ML::FeatureSchema;
use Market::ML::StandardScaler;
use Market::ML::KNNClassifier;
use Market::ML::GaussianMixtureModel;
use Market::ML::HiddenMarkovModel;

sub new {
    my ($class, %args) = @_;
    return bless {
        labels        => $args{labels} // [qw(RUN GRAB SWEEP)],
        random_runs   => $args{random_runs} // 30,
        random_seed   => $args{random_seed} // 42,
    }, $class;
}

sub evaluate_baselines {
    my ($self, %args) = @_;
    my $train_rows = $args{train_rows} // [];
    my $test_rows  = $args{test_rows}  // [];

    die "train_rows debe ser ARRAY\n" if ref($train_rows) ne 'ARRAY';
    die "test_rows debe ser ARRAY\n" if ref($test_rows) ne 'ARRAY';
    die "El conjunto de entrenamiento está vacío\n" if !@$train_rows;
    die "El conjunto de evaluación está vacío\n" if !@$test_rows;

    my @actual = map { uc($_->{target} // '') } @$test_rows;
    my $models = Market::ML::BaselineModels->new(seed => $self->{random_seed});
    my $metrics = Market::ML::ClassificationMetrics->new(labels => $self->{labels});

    my ($zero_predictions, $majority, $distribution) =
        $models->zero_rule_predict(
            train_rows => $train_rows,
            test_rows  => $test_rows,
        );

    my $zero_report = $metrics->evaluate(
        actual    => \@actual,
        predicted => $zero_predictions,
    );

    my @random_reports;
    for my $run (0 .. $self->{random_runs} - 1) {
        my $pred = $models->random_predict(
            train_rows => $train_rows,
            test_rows  => $test_rows,
            seed       => $self->{random_seed} + $run,
        );
        push @random_reports, $metrics->evaluate(
            actual    => \@actual,
            predicted => $pred,
        );
    }

    my $mean_accuracy = sum(map { $_->{accuracy} } @random_reports) / @random_reports;
    my $mean_macro_f1 = sum(map { $_->{macro_f1} } @random_reports) / @random_reports;

    return {
        zero_rule => {
            majority_class    => $majority,
            train_distribution => $distribution,
            report            => $zero_report,
        },
        random => {
            runs          => scalar(@random_reports),
            mean_accuracy => $mean_accuracy,
            mean_macro_f1 => $mean_macro_f1,
            first_report  => $random_reports[0],
        },
    };
}

sub print_baseline_report {
    my ($self, $result) = @_;
    my $metrics = Market::ML::ClassificationMetrics->new(labels => $self->{labels});

    print "\nClase mayoritaria de entrenamiento: "
        . $result->{zero_rule}{majority_class} . "\n";
    print "Distribución de entrenamiento:\n";
    for my $label (@{$self->{labels}}) {
        print "  $label => "
            . ($result->{zero_rule}{train_distribution}{$label} // 0)
            . "\n";
    }

    $metrics->print_report(
        'BASELINE ZERO RULE',
        $result->{zero_rule}{report},
    );

    print "\n========================================\n";
    print " BASELINE RANDOM PREDICTION\n";
    print "========================================\n";
    printf "Ejecuciones:        %d\n", $result->{random}{runs};
    printf "Accuracy promedio:  %.4f (%.2f%%)\n",
        $result->{random}{mean_accuracy},
        100 * $result->{random}{mean_accuracy};
    printf "Macro F1 promedio:  %.4f\n",
        $result->{random}{mean_macro_f1};
    print "La matriz siguiente corresponde a la primera ejecución reproducible.\n";

    $metrics->print_report(
        'RANDOM - PRIMERA EJECUCIÓN',
        $result->{random}{first_report},
    );
}

sub evaluate_walk_forward_baselines {
    my ($self, %args) = @_;
    my $folds = $args{folds} // [];
    die "folds debe ser ARRAY\n" if ref($folds) ne 'ARRAY';

    my @results;
    for my $fold (@$folds) {
        next if ref($fold) ne 'HASH';
        my $evaluation = $self->evaluate_baselines(
            train_rows => $fold->{train_rows},
            test_rows  => $fold->{evaluation_rows},
        );
        push @results, {
            %$fold,
            result => $evaluation,
        };
    }

    my $zero_accuracy = @results
        ? sum(map { $_->{result}{zero_rule}{report}{accuracy} } @results) / @results
        : 0;
    my $zero_macro_f1 = @results
        ? sum(map { $_->{result}{zero_rule}{report}{macro_f1} } @results) / @results
        : 0;
    my $random_accuracy = @results
        ? sum(map { $_->{result}{random}{mean_accuracy} } @results) / @results
        : 0;
    my $random_macro_f1 = @results
        ? sum(map { $_->{result}{random}{mean_macro_f1} } @results) / @results
        : 0;

    return {
        folds => \@results,
        summary => {
            fold_count            => scalar(@results),
            zero_mean_accuracy    => $zero_accuracy,
            zero_mean_macro_f1    => $zero_macro_f1,
            random_mean_accuracy  => $random_accuracy,
            random_mean_macro_f1  => $random_macro_f1,
        },
    };
}

sub print_walk_forward_report {
    my ($self, $walk) = @_;

    print "\n========================================\n";
    print " WALK-FORWARD DE DESARROLLO - BASELINES\n";
    print "========================================\n";

    for my $fold (@{$walk->{folds}}) {
        my $r = $fold->{result};
        print "Fold $fold->{fold}: ";
        print join(' + ', @{$fold->{train_group_names}});
        print " -> $fold->{evaluation_group}\n";
        printf "  Train=%d  Evaluación=%d\n",
            scalar(@{$fold->{train_rows}}),
            scalar(@{$fold->{evaluation_rows}});
        printf "  Zero Rule: accuracy=%.4f macro_f1=%.4f clase=%s\n",
            $r->{zero_rule}{report}{accuracy},
            $r->{zero_rule}{report}{macro_f1},
            $r->{zero_rule}{majority_class};
        printf "  Random(%d): accuracy=%.4f macro_f1=%.4f\n",
            $r->{random}{runs},
            $r->{random}{mean_accuracy},
            $r->{random}{mean_macro_f1};
    }

    my $s = $walk->{summary};
    print "----------------------------------------\n";
    printf "Promedio Zero Rule: accuracy=%.4f macro_f1=%.4f\n",
        $s->{zero_mean_accuracy}, $s->{zero_mean_macro_f1};
    printf "Promedio Random:    accuracy=%.4f macro_f1=%.4f\n",
        $s->{random_mean_accuracy}, $s->{random_mean_macro_f1};
    print "El conjunto TEST FINAL no participa en estos folds.\n";
    print "========================================\n";
}


sub evaluate_decision_tree {
    my ($self, %args) = @_;
    my $train_rows = $args{train_rows} // [];
    my $test_rows  = $args{test_rows}  // [];
    my $max_depth  = $args{max_depth}  // 3;
    my $features   = $args{feature_columns};

    die "El conjunto de entrenamiento está vacío\n" if !@$train_rows;
    die "El conjunto de evaluación está vacío\n" if !@$test_rows;

    $features = Market::ML::FeatureSchema->select_feature_columns(
        rows => $train_rows,
    ) if ref($features) ne 'ARRAY' || !@$features;

    my $model = Market::ML::DecisionTreeClassifier->new(
        max_depth         => $max_depth,
        min_samples_split => 10,
        min_samples_leaf  => 5,
        labels            => $self->{labels},
        feature_columns   => $features,
    );
    $model->fit(rows => $train_rows);
    my $pred = $model->predict(rows => $test_rows);
    my @actual = map { uc($_->{target} // '') } @$test_rows;
    my $metrics = Market::ML::ClassificationMetrics->new(labels => $self->{labels});
    my $report = $metrics->evaluate(actual => \@actual, predicted => $pred);

    return {
        max_depth          => $max_depth,
        report             => $report,
        model              => $model,
        node_count         => $model->node_count,
        depth_reached      => $model->depth_reached,
        feature_columns    => $model->feature_columns,
        feature_importance => $model->feature_importances,
        actual             => \@actual,
        predicted          => $pred,
    };
}

sub evaluate_walk_forward_decision_trees {
    my ($self, %args) = @_;
    my $folds  = $args{folds} // [];
    my $depths = $args{depths} // [2, 3, 4, 5];
    die "folds debe ser ARRAY\n" if ref($folds) ne 'ARRAY';

    my @configs;
    for my $depth (@$depths) {
        my @fold_results;
        for my $fold (@$folds) {
            my $result = $self->evaluate_decision_tree(
                train_rows => $fold->{train_rows},
                test_rows  => $fold->{evaluation_rows},
                max_depth  => $depth,
            );
            push @fold_results, { %$fold, result => $result };
        }
        my $mean_accuracy = @fold_results
            ? sum(map { $_->{result}{report}{accuracy} } @fold_results) / @fold_results : 0;
        my $mean_macro_f1 = @fold_results
            ? sum(map { $_->{result}{report}{macro_f1} } @fold_results) / @fold_results : 0;

        my (@pooled_actual, @pooled_predicted);
        for my $fold_result (@fold_results) {
            push @pooled_actual, @{$fold_result->{result}{actual}};
            push @pooled_predicted, @{$fold_result->{result}{predicted}};
        }
        my $metrics = Market::ML::ClassificationMetrics->new(labels => $self->{labels});
        my $pooled_report = $metrics->evaluate(
            actual    => \@pooled_actual,
            predicted => \@pooled_predicted,
        );

        push @configs, {
            max_depth     => $depth,
            folds         => \@fold_results,
            mean_accuracy => $mean_accuracy,
            mean_macro_f1 => $mean_macro_f1,
            pooled_report => $pooled_report,
        };
    }

    my @ranked = sort {
        $b->{pooled_report}{macro_f1} <=> $a->{pooled_report}{macro_f1}
        || $b->{pooled_report}{accuracy} <=> $a->{pooled_report}{accuracy}
        || $a->{max_depth} <=> $b->{max_depth}
    } @configs;

    return {
        configurations => \@configs,
        selected       => $ranked[0],
    };
}

sub print_decision_tree_selection_report {
    my ($self, $selection) = @_;
    print "\n========================================\n";
    print " ÁRBOL DE DECISIÓN - WALK-FORWARD\n";
    print "========================================\n";
    for my $config (@{$selection->{configurations}}) {
        printf "max_depth=%d  pooled_accuracy=%.4f  pooled_macro_f1=%.4f  media_folds_macro_f1=%.4f\n",
            $config->{max_depth}, $config->{pooled_report}{accuracy},
            $config->{pooled_report}{macro_f1}, $config->{mean_macro_f1};
        for my $fold (@{$config->{folds}}) {
            printf "  Fold %d: train=%d evaluación=%d accuracy=%.4f macro_f1=%.4f nodos=%d profundidad_real=%d\n",
                $fold->{fold}, scalar(@{$fold->{train_rows}}), scalar(@{$fold->{evaluation_rows}}),
                $fold->{result}{report}{accuracy}, $fold->{result}{report}{macro_f1},
                $fold->{result}{node_count}, $fold->{result}{depth_reached};
        }
    }
    my $best = $selection->{selected};
    print "----------------------------------------\n";
    printf "Configuración seleccionada: max_depth=%d\n", $best->{max_depth};
    printf "Macro F1 acumulado walk-forward: %.4f\n", $best->{pooled_report}{macro_f1};
    printf "Accuracy acumulada walk-forward: %.4f\n", $best->{pooled_report}{accuracy};
    printf "Macro F1 medio por folds: %.4f\n", $best->{mean_macro_f1};
    print "Criterio: mayor Macro F1 acumulado; desempate por accuracy acumulada y menor profundidad.\n";
    print "========================================\n";
}

sub print_decision_tree_validation_report {
    my ($self, $result) = @_;
    my $metrics = Market::ML::ClassificationMetrics->new(labels => $self->{labels});
    $metrics->print_report(
        'ÁRBOL DE DECISIÓN SELECCIONADO - TRAIN -> VALIDATION',
        $result->{report},
    );
    print "Complejidad del árbol:\n";
    print "  max_depth configurado: $result->{max_depth}\n";
    print "  profundidad alcanzada: $result->{depth_reached}\n";
    print "  nodos totales:         $result->{node_count}\n";
    print "  variables candidatas:  " . scalar(@{$result->{feature_columns}}) . "\n";
    print "Variables excluidas obligatoriamente: metadata, timestamps, target, liquidity_state, swept_index y resolved_index.\n";

    my @important = sort { $result->{feature_importance}{$b} <=> $result->{feature_importance}{$a} }
        keys %{$result->{feature_importance}};
    print "Top variables utilizadas:\n";
    my $limit = @important < 12 ? scalar(@important) : 12;
    for my $i (0 .. $limit - 1) {
        my $f = $important[$i];
        printf "  %2d. %-38s %.4f\n", $i + 1, $f, $result->{feature_importance}{$f};
    }
}


sub evaluate_knn {
    my ($self, %args) = @_;
    my $train_rows = $args{train_rows} // [];
    my $test_rows  = $args{test_rows}  // [];
    my $k          = $args{k} // 5;
    my $features   = $args{feature_columns};

    die "El conjunto de entrenamiento está vacío\n" if !@$train_rows;
    die "El conjunto de evaluación está vacío\n" if !@$test_rows;

    $features = Market::ML::FeatureSchema->select_feature_columns(
        rows => $train_rows,
    ) if ref($features) ne 'ARRAY' || !@$features;

    my $scaler = Market::ML::StandardScaler->new(
        feature_columns => $features,
    );
    my $train_vectors = $scaler->fit_transform(rows => $train_rows);
    my $test_vectors  = $scaler->transform(rows => $test_rows);
    my @train_labels  = map { uc($_->{target} // '') } @$train_rows;
    my @actual        = map { uc($_->{target} // '') } @$test_rows;

    my $model = Market::ML::KNNClassifier->new(
        k      => $k,
        labels => $self->{labels},
    );
    $model->fit(vectors => $train_vectors, labels => \@train_labels);
    my $pred = $model->predict(vectors => $test_vectors);

    my $metrics = Market::ML::ClassificationMetrics->new(labels => $self->{labels});
    my $report = $metrics->evaluate(actual => \@actual, predicted => $pred);

    return {
        k                         => $k,
        report                    => $report,
        model                     => $model,
        scaler                    => $scaler,
        feature_columns           => $features,
        transformed_feature_count => scalar(@{$scaler->output_features}),
        numeric_feature_count     => $scaler->numeric_feature_count,
        categorical_feature_count => $scaler->categorical_feature_count,
        actual                    => \@actual,
        predicted                 => $pred,
    };
}

sub evaluate_walk_forward_knn {
    my ($self, %args) = @_;
    my $folds = $args{folds} // [];
    my $k_values = $args{k_values} // [3, 5, 7, 9, 11];
    die "folds debe ser ARRAY\n" if ref($folds) ne 'ARRAY';

    my @configs;
    for my $k (@$k_values) {
        my @fold_results;
        for my $fold (@$folds) {
            my $result = $self->evaluate_knn(
                train_rows => $fold->{train_rows},
                test_rows  => $fold->{evaluation_rows},
                k          => $k,
            );
            push @fold_results, { %$fold, result => $result };
        }

        my $mean_accuracy = @fold_results
            ? sum(map { $_->{result}{report}{accuracy} } @fold_results) / @fold_results : 0;
        my $mean_macro_f1 = @fold_results
            ? sum(map { $_->{result}{report}{macro_f1} } @fold_results) / @fold_results : 0;

        my (@pooled_actual, @pooled_predicted);
        for my $fold_result (@fold_results) {
            push @pooled_actual, @{$fold_result->{result}{actual}};
            push @pooled_predicted, @{$fold_result->{result}{predicted}};
        }
        my $metrics = Market::ML::ClassificationMetrics->new(labels => $self->{labels});
        my $pooled_report = $metrics->evaluate(
            actual    => \@pooled_actual,
            predicted => \@pooled_predicted,
        );

        push @configs, {
            k             => $k,
            folds         => \@fold_results,
            mean_accuracy => $mean_accuracy,
            mean_macro_f1 => $mean_macro_f1,
            pooled_report => $pooled_report,
        };
    }

    my @ranked = sort {
        $b->{pooled_report}{macro_f1} <=> $a->{pooled_report}{macro_f1}
        || $b->{pooled_report}{accuracy} <=> $a->{pooled_report}{accuracy}
        || $a->{k} <=> $b->{k}
    } @configs;

    return {
        configurations => \@configs,
        selected       => $ranked[0],
    };
}

sub print_knn_selection_report {
    my ($self, $selection) = @_;
    print "\n========================================\n";
    print " K-NEAREST NEIGHBORS - WALK-FORWARD\n";
    print "========================================\n";
    for my $config (@{$selection->{configurations}}) {
        printf "k=%d  pooled_accuracy=%.4f  pooled_macro_f1=%.4f  media_folds_macro_f1=%.4f\n",
            $config->{k}, $config->{pooled_report}{accuracy},
            $config->{pooled_report}{macro_f1}, $config->{mean_macro_f1};
        for my $fold (@{$config->{folds}}) {
            printf "  Fold %d: train=%d evaluación=%d accuracy=%.4f macro_f1=%.4f dimensiones=%d\n",
                $fold->{fold}, scalar(@{$fold->{train_rows}}), scalar(@{$fold->{evaluation_rows}}),
                $fold->{result}{report}{accuracy}, $fold->{result}{report}{macro_f1},
                $fold->{result}{transformed_feature_count};
        }
    }
    my $best = $selection->{selected};
    print "----------------------------------------\n";
    printf "Configuración seleccionada: k=%d\n", $best->{k};
    printf "Macro F1 acumulado walk-forward: %.4f\n", $best->{pooled_report}{macro_f1};
    printf "Accuracy acumulada walk-forward: %.4f\n", $best->{pooled_report}{accuracy};
    printf "Macro F1 medio por folds: %.4f\n", $best->{mean_macro_f1};
    print "Criterio: mayor Macro F1 acumulado; desempate por accuracy acumulada y menor k.\n";
    print "El StandardScaler se ajustó exclusivamente con el TRAIN de cada fold.\n";
    print "========================================\n";
}

sub print_knn_validation_report {
    my ($self, $result) = @_;
    my $metrics = Market::ML::ClassificationMetrics->new(labels => $self->{labels});
    $metrics->print_report(
        'K-NN SELECCIONADO - TRAIN -> VALIDATION',
        $result->{report},
    );
    print "Configuración de k-NN:\n";
    print "  k seleccionado:              $result->{k}\n";
    print "  variables originales:        " . scalar(@{$result->{feature_columns}}) . "\n";
    print "  variables numéricas:         $result->{numeric_feature_count}\n";
    print "  variables categóricas:       $result->{categorical_feature_count}\n";
    print "  dimensiones tras one-hot:    $result->{transformed_feature_count}\n";
    print "  distancia:                    euclidiana\n";
    print "  escalamiento:                 media y desviación calculadas solo con TRAIN\n";
    print "Variables excluidas obligatoriamente: metadata, timestamps, target, liquidity_state, swept_index y resolved_index.\n";
}


sub evaluate_gmm {
    my ($self, %args) = @_;
    my $train_rows = $args{train_rows} // [];
    my $test_rows  = $args{test_rows}  // [];
    my $components = $args{components} // 3;
    my $features   = $args{feature_columns};
    my $seed       = $args{seed} // $self->{random_seed};

    die "El conjunto de entrenamiento está vacío\n" if !@$train_rows;
    die "El conjunto de evaluación está vacío\n" if !@$test_rows;

    $features = Market::ML::FeatureSchema->select_feature_columns(
        rows => $train_rows,
    ) if ref($features) ne 'ARRAY' || !@$features;

    my $scaler = Market::ML::StandardScaler->new(feature_columns => $features);
    my $train_vectors = $scaler->fit_transform(rows => $train_rows);
    my $test_vectors  = $scaler->transform(rows => $test_rows);
    my @train_labels  = map { uc($_->{target} // '') } @$train_rows;
    my @actual        = map { uc($_->{target} // '') } @$test_rows;

    my $model = Market::ML::GaussianMixtureModel->new(
        components     => $components,
        max_iterations => 200,
        tolerance      => 1e-5,
        regularization => 1e-3,
        seed           => $seed,
    );
    $model->fit(vectors => $train_vectors);

    my $train_components = $model->predict_components(vectors => $train_vectors);
    my $component_labels = _map_components_to_labels(
        components => $train_components,
        labels     => \@train_labels,
        all_labels => $self->{labels},
    );

    my $test_components = $model->predict_components(vectors => $test_vectors);
    my @predicted = map { $component_labels->{$_} } @$test_components;
    my $metrics = Market::ML::ClassificationMetrics->new(labels => $self->{labels});
    my $report = $metrics->evaluate(actual => \@actual, predicted => \@predicted);

    my %component_sizes;
    $component_sizes{$_}++ for @$train_components;

    return {
        components                => $components,
        report                    => $report,
        model                     => $model,
        scaler                    => $scaler,
        feature_columns           => $features,
        transformed_feature_count => scalar(@{$scaler->output_features}),
        numeric_feature_count     => $scaler->numeric_feature_count,
        categorical_feature_count => $scaler->categorical_feature_count,
        component_labels          => $component_labels,
        component_sizes           => \%component_sizes,
        train_log_likelihood       => $model->log_likelihood,
        evaluation_log_likelihood  => $model->score(vectors => $test_vectors),
        train_bic                  => $model->bic(vectors => $train_vectors),
        converged                  => $model->converged,
        iterations                 => $model->iterations,
        actual                     => \@actual,
        predicted                  => \@predicted,
    };
}

sub evaluate_walk_forward_gmm {
    my ($self, %args) = @_;
    my $folds = $args{folds} // [];
    my $component_values = $args{component_values} // [2, 3, 4, 5];
    die "folds debe ser ARRAY\n" if ref($folds) ne 'ARRAY';

    my @configs;
    for my $components (@$component_values) {
        my @fold_results;
        for my $fold (@$folds) {
            my $result = $self->evaluate_gmm(
                train_rows => $fold->{train_rows},
                test_rows  => $fold->{evaluation_rows},
                components => $components,
                seed       => $self->{random_seed} + $fold->{fold},
            );
            push @fold_results, { %$fold, result => $result };
        }

        my $mean_accuracy = @fold_results
            ? sum(map { $_->{result}{report}{accuracy} } @fold_results) / @fold_results : 0;
        my $mean_macro_f1 = @fold_results
            ? sum(map { $_->{result}{report}{macro_f1} } @fold_results) / @fold_results : 0;
        my $mean_bic = @fold_results
            ? sum(map { $_->{result}{train_bic} } @fold_results) / @fold_results : 0;

        my (@pooled_actual, @pooled_predicted);
        for my $fold_result (@fold_results) {
            push @pooled_actual, @{$fold_result->{result}{actual}};
            push @pooled_predicted, @{$fold_result->{result}{predicted}};
        }
        my $metrics = Market::ML::ClassificationMetrics->new(labels => $self->{labels});
        my $pooled_report = $metrics->evaluate(
            actual    => \@pooled_actual,
            predicted => \@pooled_predicted,
        );

        push @configs, {
            components    => $components,
            folds         => \@fold_results,
            mean_accuracy => $mean_accuracy,
            mean_macro_f1 => $mean_macro_f1,
            mean_bic      => $mean_bic,
            pooled_report => $pooled_report,
        };
    }

    my @ranked = sort {
        $b->{pooled_report}{macro_f1} <=> $a->{pooled_report}{macro_f1}
        || $b->{pooled_report}{accuracy} <=> $a->{pooled_report}{accuracy}
        || $a->{mean_bic} <=> $b->{mean_bic}
        || $a->{components} <=> $b->{components}
    } @configs;

    return {
        configurations => \@configs,
        selected       => $ranked[0],
    };
}

sub print_gmm_selection_report {
    my ($self, $selection) = @_;
    print "\n========================================\n";
    print " GAUSSIAN MIXTURE MODEL - WALK-FORWARD\n";
    print "========================================\n";
    for my $config (@{$selection->{configurations}}) {
        printf "componentes=%d  pooled_accuracy=%.4f  pooled_macro_f1=%.4f  BIC_medio=%.2f\n",
            $config->{components}, $config->{pooled_report}{accuracy},
            $config->{pooled_report}{macro_f1}, $config->{mean_bic};
        for my $fold (@{$config->{folds}}) {
            printf "  Fold %d: train=%d evaluación=%d accuracy=%.4f macro_f1=%.4f iter=%d convergió=%s dimensiones=%d\n",
                $fold->{fold}, scalar(@{$fold->{train_rows}}), scalar(@{$fold->{evaluation_rows}}),
                $fold->{result}{report}{accuracy}, $fold->{result}{report}{macro_f1},
                $fold->{result}{iterations}, $fold->{result}{converged} ? 'sí' : 'no',
                $fold->{result}{transformed_feature_count};
        }
    }
    my $best = $selection->{selected};
    print "----------------------------------------\n";
    printf "Configuración seleccionada: componentes=%d\n", $best->{components};
    printf "Macro F1 acumulado walk-forward: %.4f\n", $best->{pooled_report}{macro_f1};
    printf "Accuracy acumulada walk-forward: %.4f\n", $best->{pooled_report}{accuracy};
    printf "BIC medio de entrenamiento: %.2f\n", $best->{mean_bic};
    print "Criterio: mayor Macro F1 acumulado; desempate por accuracy, menor BIC y menor número de componentes.\n";
    print "Cada GMM y su StandardScaler se ajustaron exclusivamente con TRAIN del fold.\n";
    print "========================================\n";
}

sub print_gmm_validation_report {
    my ($self, $result) = @_;
    my $metrics = Market::ML::ClassificationMetrics->new(labels => $self->{labels});
    $metrics->print_report(
        'GMM SELECCIONADO - TRAIN -> VALIDATION',
        $result->{report},
    );
    print "Configuración estadística del GMM:\n";
    print "  componentes gaussianos:       $result->{components}\n";
    print "  tipo de covarianza:            diagonal\n";
    print "  iteraciones EM:                $result->{iterations}\n";
    print "  convergencia:                  " . ($result->{converged} ? 'sí' : 'no') . "\n";
    printf "  log-verosimilitud TRAIN:       %.4f\n", $result->{train_log_likelihood};
    printf "  log-verosimilitud VALIDATION:  %.4f\n", $result->{evaluation_log_likelihood};
    printf "  BIC TRAIN:                     %.4f\n", $result->{train_bic};
    print "  variables originales:          " . scalar(@{$result->{feature_columns}}) . "\n";
    print "  dimensiones tras one-hot:      $result->{transformed_feature_count}\n";
    print "Mapeo aprendido exclusivamente con etiquetas TRAIN:\n";
    for my $component (0 .. $result->{components} - 1) {
        printf "  componente %d -> %-5s  filas_train=%d\n",
            $component,
            $result->{component_labels}{$component},
            $result->{component_sizes}{$component} // 0;
    }
    print "TEST FINAL continúa reservado.\n";
}


sub evaluate_hmm {
    my ($self, %args) = @_;
    my $train_rows = $args{train_rows} // [];
    my $test_rows  = $args{test_rows}  // [];
    my $smoothing  = defined($args{smoothing}) ? 0 + $args{smoothing} : 1.0;
    my $features   = $args{feature_columns};

    die "El conjunto de entrenamiento está vacío\n" if !@$train_rows;
    die "El conjunto de evaluación está vacío\n" if !@$test_rows;

    $features = Market::ML::FeatureSchema->select_feature_columns(
        rows => $train_rows,
    ) if ref($features) ne 'ARRAY' || !@$features;

    my $scaler = Market::ML::StandardScaler->new(feature_columns => $features);
    my $train_vectors = $scaler->fit_transform(rows => $train_rows);
    my $test_vectors  = $scaler->transform(rows => $test_rows);
    my @train_labels  = map { uc($_->{target} // '') } @$train_rows;
    my @actual        = map { uc($_->{target} // '') } @$test_rows;
    my @train_sequences = map { _sequence_id($_) } @$train_rows;
    my @test_sequences  = map { _sequence_id($_) } @$test_rows;

    my $model = Market::ML::HiddenMarkovModel->new(
        states         => $self->{labels},
        smoothing      => $smoothing,
        variance_floor => 1e-2,
    );
    $model->fit(
        vectors      => $train_vectors,
        labels       => \@train_labels,
        sequence_ids => \@train_sequences,
    );

    my ($online_predictions, $posteriors) = $model->predict_online(
        vectors      => $test_vectors,
        sequence_ids => \@test_sequences,
    );
    my $viterbi_predictions = $model->viterbi(
        vectors      => $test_vectors,
        sequence_ids => \@test_sequences,
    );

    my $metrics = Market::ML::ClassificationMetrics->new(labels => $self->{labels});
    my $online_report = $metrics->evaluate(
        actual    => \@actual,
        predicted => $online_predictions,
    );
    my $viterbi_report = $metrics->evaluate(
        actual    => \@actual,
        predicted => $viterbi_predictions,
    );

    return {
        smoothing                  => $smoothing,
        report                     => $online_report,
        viterbi_report             => $viterbi_report,
        model                      => $model,
        scaler                     => $scaler,
        feature_columns            => $features,
        transformed_feature_count  => scalar(@{$scaler->output_features}),
        numeric_feature_count      => $scaler->numeric_feature_count,
        categorical_feature_count  => $scaler->categorical_feature_count,
        train_log_likelihood        => $model->train_log_likelihood,
        evaluation_log_likelihood   => $model->score(
            vectors      => $test_vectors,
            sequence_ids => \@test_sequences,
        ),
        initial_probabilities       => $model->initial_probabilities,
        transition_matrix          => $model->transition_matrix,
        state_counts               => $model->state_counts,
        actual                     => \@actual,
        predicted                  => $online_predictions,
        viterbi_predicted          => $viterbi_predictions,
        posteriors                 => $posteriors,
    };
}

sub evaluate_walk_forward_hmm {
    my ($self, %args) = @_;
    my $folds = $args{folds} // [];
    my $smoothing_values = $args{smoothing_values} // [0.1, 0.5, 1.0, 2.0];
    die "folds debe ser ARRAY\n" if ref($folds) ne 'ARRAY';

    my @configs;
    for my $smoothing (@$smoothing_values) {
        my @fold_results;
        for my $fold (@$folds) {
            my $result = $self->evaluate_hmm(
                train_rows => $fold->{train_rows},
                test_rows  => $fold->{evaluation_rows},
                smoothing  => $smoothing,
            );
            push @fold_results, { %$fold, result => $result };
        }

        my (@pooled_actual, @pooled_predicted);
        for my $fold_result (@fold_results) {
            push @pooled_actual, @{$fold_result->{result}{actual}};
            push @pooled_predicted, @{$fold_result->{result}{predicted}};
        }
        my $metrics = Market::ML::ClassificationMetrics->new(labels => $self->{labels});
        my $pooled_report = $metrics->evaluate(
            actual    => \@pooled_actual,
            predicted => \@pooled_predicted,
        );
        my $mean_macro_f1 = @fold_results
            ? sum(map { $_->{result}{report}{macro_f1} } @fold_results) / @fold_results : 0;
        my $mean_accuracy = @fold_results
            ? sum(map { $_->{result}{report}{accuracy} } @fold_results) / @fold_results : 0;

        push @configs, {
            smoothing      => $smoothing,
            folds          => \@fold_results,
            pooled_report  => $pooled_report,
            mean_macro_f1  => $mean_macro_f1,
            mean_accuracy  => $mean_accuracy,
        };
    }

    my @ranked = sort {
        $b->{pooled_report}{macro_f1} <=> $a->{pooled_report}{macro_f1}
        || $b->{pooled_report}{accuracy} <=> $a->{pooled_report}{accuracy}
        || $a->{smoothing} <=> $b->{smoothing}
    } @configs;

    return {
        configurations => \@configs,
        selected       => $ranked[0],
    };
}

sub print_hmm_selection_report {
    my ($self, $selection) = @_;
    print "\n========================================\n";
    print " HIDDEN MARKOV MODEL - WALK-FORWARD CAUSAL\n";
    print "========================================\n";
    for my $config (@{$selection->{configurations}}) {
        printf "suavizado=%.2f  pooled_accuracy=%.4f  pooled_macro_f1=%.4f  media_folds_macro_f1=%.4f\n",
            $config->{smoothing}, $config->{pooled_report}{accuracy},
            $config->{pooled_report}{macro_f1}, $config->{mean_macro_f1};
        for my $fold (@{$config->{folds}}) {
            printf "  Fold %d: train=%d evaluación=%d accuracy=%.4f macro_f1=%.4f dimensiones=%d\n",
                $fold->{fold}, scalar(@{$fold->{train_rows}}), scalar(@{$fold->{evaluation_rows}}),
                $fold->{result}{report}{accuracy}, $fold->{result}{report}{macro_f1},
                $fold->{result}{transformed_feature_count};
        }
    }
    my $best = $selection->{selected};
    print "----------------------------------------\n";
    printf "Suavizado seleccionado: %.2f\n", $best->{smoothing};
    printf "Macro F1 acumulado walk-forward: %.4f\n", $best->{pooled_report}{macro_f1};
    printf "Accuracy acumulada walk-forward: %.4f\n", $best->{pooled_report}{accuracy};
    print "Criterio: mayor Macro F1 causal; desempate por accuracy y menor suavizado.\n";
    print "La predicción evaluada usa filtrado hacia adelante y no observa pivotes futuros.\n";
    print "========================================\n";
}

sub print_hmm_validation_report {
    my ($self, $result) = @_;
    my $metrics = Market::ML::ClassificationMetrics->new(labels => $self->{labels});
    $metrics->print_report(
        'HMM CAUSAL SELECCIONADO - TRAIN -> VALIDATION',
        $result->{report},
    );
    print "Configuración estadística del HMM:\n";
    printf "  suavizado de Laplace:           %.2f\n", $result->{smoothing};
    print "  estados ocultos:                 " . join(', ', @{$self->{labels}}) . "\n";
    print "  emisiones:                       gaussianas diagonales\n";
    print "  decodificación evaluada:         filtrado causal hacia adelante\n";
    print "  dimensiones tras one-hot:        $result->{transformed_feature_count}\n";
    printf "  log-verosimilitud TRAIN:         %.4f\n", $result->{train_log_likelihood};
    printf "  log-verosimilitud VALIDATION:    %.4f\n", $result->{evaluation_log_likelihood};

    print "Vector inicial pi:\n";
    for my $state (@{$self->{labels}}) {
        printf "  P(%s al iniciar)=%.4f\n", $state, $result->{initial_probabilities}{$state};
    }
    print "Matriz de transición A (origen -> destino):\n";
    printf "%-10s", 'ORIGEN';
    printf "%10s", $_ for @{$self->{labels}};
    print "\n";
    for my $from (@{$self->{labels}}) {
        printf "%-10s", $from;
        printf "%10.4f", $result->{transition_matrix}{$from}{$_} for @{$self->{labels}};
        print "\n";
    }
    print "Comparación académica: Viterbi usa la secuencia completa y no se usa para seleccionar el modelo.\n";
    printf "  Viterbi accuracy=%.4f macro_f1=%.4f\n",
        $result->{viterbi_report}{accuracy}, $result->{viterbi_report}{macro_f1};
    print "TEST FINAL continúa reservado.\n";
}

sub _sequence_id {
    my ($row) = @_;
    return join('|',
        $row->{source_file} // $row->{dataset_date} // 'UNKNOWN',
        $row->{symbol} // 'MARKET',
        $row->{timeframe} // '1',
    );
}

sub _map_components_to_labels {
    my (%args) = @_;
    my $components = $args{components} // [];
    my $labels = $args{labels} // [];
    my $all_labels = $args{all_labels} // [qw(RUN GRAB SWEEP)];
    die "Cantidad distinta de componentes y etiquetas\n" if @$components != @$labels;

    my (%counts, %global);
    for my $i (0 .. $#$components) {
        my $label = uc($labels->[$i] // '');
        $counts{$components->[$i]}{$label}++;
        $global{$label}++;
    }
    my %order = map { $all_labels->[$_] => $_ } 0 .. $#$all_labels;
    my @global_rank = sort {
        ($global{$b} // 0) <=> ($global{$a} // 0)
        || ($order{$a} // 999) <=> ($order{$b} // 999)
    } @$all_labels;
    my $fallback = $global_rank[0] // $all_labels->[0];

    my %mapping;
    my $maximum_component = @$components ? max(@$components) : -1;
    for my $component (0 .. $maximum_component) {
        my @ranked = sort {
            ($counts{$component}{$b} // 0) <=> ($counts{$component}{$a} // 0)
            || ($order{$a} // 999) <=> ($order{$b} // 999)
        } @$all_labels;
        $mapping{$component} = ($counts{$component}{$ranked[0]} // 0) > 0
            ? $ranked[0] : $fallback;
    }
    return \%mapping;
}

1;
