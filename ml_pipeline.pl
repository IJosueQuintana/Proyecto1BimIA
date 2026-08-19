use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use lib "$FindBin::Bin/Market";
use lib ".";

use File::Path qw(make_path);
use Market::ML::DatasetPipeline;
use Market::ML::DatasetExporter;
use Market::ML::CausalityAuditor;
use Market::ML::TestHarness;
use Market::ML::TemporalSplit;

# ================================================================
# PARTICIONAMIENTO TEMPORAL PRINCIPAL
#
# No se aplica un porcentaje aleatorio 60/40, 70/30 u 80/20.
# Cada sesión completa conserva su orden para evitar fuga temporal.
# ================================================================
my @train_files = (
    "$FindBin::Bin/2026_03.csv",
    "$FindBin::Bin/2026_06_29.csv",
    "$FindBin::Bin/2026_07_06.csv",
);

my @validation_files = (
    "$FindBin::Bin/2026_07_13.csv",
);

my @test_files = (
    "$FindBin::Bin/2026_07_20.csv",
);

my $output_dir = "$FindBin::Bin/datasets/ml_pipeline";
make_path($output_dir) if !-d $output_dir;

my $pipeline = Market::ML::DatasetPipeline->new(
    symbol          => 'MARKET',
    timeframe       => 1,
    volume_lookback => 20,
);

my $exporter = Market::ML::DatasetExporter->new();
my $temporal = Market::ML::TemporalSplit->new();

my %result_by_file;

sub process_group {
    my ($name, $files) = @_;
    my @all_rows;
    my @all_trainable;
    my $columns;

    print "\n========================================\n";
    print " GENERANDO SPLIT TEMPORAL: " . uc($name) . "\n";
    print "========================================\n";

    for my $file (@$files) {
        die "Falta el archivo requerido: $file\n" if !-f $file;

        print "Procesando $file ...\n";
        my $result = $pipeline->build_file_dataset(file => $file);
        $columns //= $result->{columns};
        $result_by_file{$file} = $result;

        push @all_rows, @{$result->{rows}};
        push @all_trainable, @{$result->{trainable}};

        my $base = $result->{dataset_date};
        $exporter->export_csv(
            file    => "$output_dir/${base}_all.csv",
            rows    => $result->{rows},
            columns => $columns,
        );
        $exporter->export_csv(
            file    => "$output_dir/${base}_trainable.csv",
            rows    => $result->{trainable},
            columns => $columns,
        );

        print "  Velas: " . $result->{candle_count} . "\n";
        print "  Filas generales: " . scalar(@{$result->{rows}}) . "\n";
        print "  Filas entrenables: " . scalar(@{$result->{trainable}}) . "\n";
        print "  Filas inválidas: " . ($result->{validation}{invalid_rows} // 0) . "\n";
    }

    my $sorted_rows = $temporal->sort_rows(\@all_rows);
    my $sorted_trainable = $temporal->sort_rows(\@all_trainable);

    $exporter->export_csv(
        file    => "$output_dir/${name}_all.csv",
        rows    => $sorted_rows,
        columns => $columns,
    );
    $exporter->export_csv(
        file    => "$output_dir/${name}_trainable.csv",
        rows    => $sorted_trainable,
        columns => $columns,
    );

    print "TOTAL $name general: " . scalar(@$sorted_rows) . "\n";
    print "TOTAL $name entrenable: " . scalar(@$sorted_trainable) . "\n";

    return {
        rows      => $sorted_rows,
        trainable => $sorted_trainable,
        columns   => $columns,
    };
}

my $train = process_group('train', \@train_files);
my $validation = process_group('validation', \@validation_files);
my $test = process_group('test', \@test_files);

# Los snapshots de julio son acumulativos desde el 1 de julio.
# Conservamos el historial completo para calcular indicadores, pero eliminamos
# de cada split las filas ML que ya pertenecen al split anterior.
my $train_end = $temporal->latest_timestamp($train->{trainable});
$validation->{rows} = $temporal->filter_after_timestamp(
    rows  => $validation->{rows},
    after => $train_end,
);
$validation->{trainable} = $temporal->filter_after_timestamp(
    rows  => $validation->{trainable},
    after => $train_end,
);

my $validation_end = $temporal->latest_timestamp($validation->{trainable});
$test->{rows} = $temporal->filter_after_timestamp(
    rows  => $test->{rows},
    after => $validation_end,
);
$test->{trainable} = $temporal->filter_after_timestamp(
    rows  => $test->{trainable},
    after => $validation_end,
);

# Reexportar los splits finales ya depurados y sin solapamientos.
$exporter->export_csv(
    file    => "$output_dir/validation_all.csv",
    rows    => $validation->{rows},
    columns => $validation->{columns},
);
$exporter->export_csv(
    file    => "$output_dir/validation_trainable.csv",
    rows    => $validation->{trainable},
    columns => $validation->{columns},
);
$exporter->export_csv(
    file    => "$output_dir/test_all.csv",
    rows    => $test->{rows},
    columns => $test->{columns},
);
$exporter->export_csv(
    file    => "$output_dir/test_trainable.csv",
    rows    => $test->{trainable},
    columns => $test->{columns},
);

print "
Filtrado temporal por timestamp real:
";
print "  Fin TRAIN:      " . ($train_end // 'N/A') . "
";
print "  Fin VALIDATION: " . ($validation_end // 'N/A') . "
";
print "  VALIDATION sin duplicados: " . scalar(@{$validation->{trainable}}) . " filas
";
print "  TEST sin duplicados:       " . scalar(@{$test->{trainable}}) . " filas
";

my @all_trainable = (
    @{$train->{trainable}},
    @{$validation->{trainable}},
    @{$test->{trainable}},
);
my $all_sorted = $temporal->sort_rows(\@all_trainable);

$exporter->export_csv(
    file    => "$output_dir/all_trainable_chronological.csv",
    rows    => $all_sorted,
    columns => $train->{columns},
);

my $temporal_report = $temporal->validate_ordered_groups(
    train_rows      => $train->{trainable},
    validation_rows => $validation->{trainable},
    test_rows       => $test->{trainable},
);
$temporal->print_validation_report($temporal_report);
die "Se detectó una mezcla temporal. Se cancela la evaluación.\n"
    if !$temporal_report->{valid};

# Auditoría causal antes de entrenar cualquier modelo. La etiqueta y sus
# índices futuros pueden permanecer en las filas para evaluación, pero el
# contrato FeatureSchema impide que sean parte del vector de entrada X.
my $causality = Market::ML::CausalityAuditor->new(
    strict       => 1,
    max_examples => 20,
);

for my $split (
    [ TRAIN      => $train->{trainable},      $train->{columns} ],
    [ VALIDATION => $validation->{trainable}, $validation->{columns} ],
    [ TEST       => $test->{trainable},       $test->{columns} ],
) {
    my ($name, $rows, $columns) = @$split;
    my $causal_report = $causality->audit_rows(
        name    => $name,
        rows    => $rows,
        columns => $columns,
    );
    $causality->print_report($causal_report);
    die "Se cancela el entrenamiento: $name contiene fuga o inconsistencia causal.\n"
        if !$causal_report->{valid};
}

print "\n========================================\n";
print " RESUMEN DE PARTICIONAMIENTO TEMPORAL\n";
print "========================================\n";
print "TRAIN:      " . scalar(@{$train->{trainable}}) . " filas\n";
print "VALIDATION: " . scalar(@{$validation->{trainable}}) . " filas\n";
print "TEST FINAL: " . scalar(@{$test->{trainable}}) . " filas\n";
print "COLUMNAS EXPORTADAS: " . scalar(@{$train->{columns}}) . "\n";
print "Método principal: sesiones completas ordenadas cronológicamente.\n";
print "No se utilizó hold-out aleatorio ni se mezclaron fechas.\n";
print "TEST FINAL permanece reservado para el modelo seleccionado.\n";
print "========================================\n";

my $harness = Market::ML::TestHarness->new(
    labels      => [qw(RUN GRAB SWEEP)],
    random_runs => 30,
    random_seed => 42,
);

# Evaluación principal para seleccionar modelos: TRAIN -> VALIDATION.
my $baseline_result = $harness->evaluate_baselines(
    train_rows => $train->{trainable},
    test_rows  => $validation->{trainable},
);
$harness->print_baseline_report($baseline_result);

# Walk-forward de desarrollo. Termina el 13 de julio y NO usa el test final.
my @development_groups;
my $previous_development_end;
for my $file (@train_files, @validation_files) {
    my $group_rows = $temporal->filter_after_timestamp(
        rows  => $result_by_file{$file}{trainable},
        after => $previous_development_end,
    );
    next if !@$group_rows;

    push @development_groups, {
        name => $result_by_file{$file}{source_file},
        rows => $group_rows,
    };
    $previous_development_end = $temporal->latest_timestamp($group_rows);
}

my $folds = $temporal->build_walk_forward_folds(
    groups => \@development_groups,
);
my $walk = $harness->evaluate_walk_forward_baselines(folds => $folds);
$harness->print_walk_forward_report($walk);


# Primer modelo supervisado real: árbol de decisión CART simplificado.
# Se selecciona la profundidad solo con los folds de desarrollo.
my $tree_selection = $harness->evaluate_walk_forward_decision_trees(
    folds  => $folds,
    depths => [2, 3, 4, 5],
);
$harness->print_decision_tree_selection_report($tree_selection);

# Una vez escogida la profundidad por walk-forward, se entrena con TRAIN
# y se informa su resultado sobre VALIDATION. TEST FINAL continúa reservado.
my $selected_depth = $tree_selection->{selected}{max_depth};
my $tree_validation = $harness->evaluate_decision_tree(
    train_rows => $train->{trainable},
    test_rows  => $validation->{trainable},
    max_depth  => $selected_depth,
);
$harness->print_decision_tree_validation_report($tree_validation);

# Segundo modelo supervisado: k-Nearest Neighbors.
# StandardScaler se ajusta dentro de cada fold solo con sus filas de TRAIN.
my $knn_selection = $harness->evaluate_walk_forward_knn(
    folds    => $folds,
    k_values => [3, 5, 7, 9, 11],
);
$harness->print_knn_selection_report($knn_selection);

# Entrenamiento final de desarrollo con TRAIN y evaluación en VALIDATION.
# TEST FINAL sigue completamente reservado.
my $selected_k = $knn_selection->{selected}{k};
my $knn_validation = $harness->evaluate_knn(
    train_rows => $train->{trainable},
    test_rows  => $validation->{trainable},
    k          => $selected_k,
);
$harness->print_knn_validation_report($knn_validation);

# Modelo estadístico no supervisado: Gaussian Mixture Model (GMM).
# El algoritmo EM aprende componentes gaussianos solo con X de TRAIN.
# Después, cada componente se asocia a RUN/GRAB/SWEEP mediante mayoría
# de etiquetas observadas exclusivamente en ese mismo TRAIN.
my $gmm_selection = $harness->evaluate_walk_forward_gmm(
    folds            => $folds,
    component_values => [2, 3, 4, 5],
);
$harness->print_gmm_selection_report($gmm_selection);

my $selected_components = $gmm_selection->{selected}{components};
my $gmm_validation = $harness->evaluate_gmm(
    train_rows => $train->{trainable},
    test_rows  => $validation->{trainable},
    components => $selected_components,
    seed       => 42,
);
$harness->print_gmm_validation_report($gmm_validation);

# Modelo Oculto de Markov: incorpora dependencia temporal entre estados.
# Los parámetros pi, A y emisiones gaussianas se estiman solo con TRAIN.
# La métrica principal usa filtrado causal hacia adelante; Viterbi se informa
# únicamente como referencia académica porque utiliza la secuencia completa.
my $hmm_selection = $harness->evaluate_walk_forward_hmm(
    folds            => $folds,
    smoothing_values => [0.1, 0.5, 1.0, 2.0],
);
$harness->print_hmm_selection_report($hmm_selection);

my $selected_smoothing = $hmm_selection->{selected}{smoothing};
my $hmm_validation = $harness->evaluate_hmm(
    train_rows => $train->{trainable},
    test_rows  => $validation->{trainable},
    smoothing  => $selected_smoothing,
);
$harness->print_hmm_validation_report($hmm_validation);

print "\n========================================\n";
print " COMPARACIÓN DE MODELOS DE DESARROLLO\n";
print "========================================\n";
printf "Árbol max_depth=%d: pooled_macro_f1=%.4f pooled_accuracy=%.4f\n",
    $tree_selection->{selected}{max_depth},
    $tree_selection->{selected}{pooled_report}{macro_f1},
    $tree_selection->{selected}{pooled_report}{accuracy};
printf "k-NN k=%d:          pooled_macro_f1=%.4f pooled_accuracy=%.4f\n",
    $knn_selection->{selected}{k},
    $knn_selection->{selected}{pooled_report}{macro_f1},
    $knn_selection->{selected}{pooled_report}{accuracy};
printf "GMM componentes=%d: pooled_macro_f1=%.4f pooled_accuracy=%.4f\n",
    $gmm_selection->{selected}{components},
    $gmm_selection->{selected}{pooled_report}{macro_f1},
    $gmm_selection->{selected}{pooled_report}{accuracy};
printf "HMM suavizado=%.2f:   pooled_macro_f1=%.4f pooled_accuracy=%.4f\n",
    $hmm_selection->{selected}{smoothing},
    $hmm_selection->{selected}{pooled_report}{macro_f1},
    $hmm_selection->{selected}{pooled_report}{accuracy};
print "Selección definitiva de desarrollo ya puede congelarse; TEST FINAL todavía no se utiliza.\n";
print "========================================\n";

print "\nArchivos generados en:\n$output_dir\n";
print "\nIMPORTANTE: 2026_07_20.csv no fue evaluado.\n";
print "Se usará una sola vez después de escoger y congelar el modelo.\n";
