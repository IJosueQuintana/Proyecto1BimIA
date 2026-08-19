package Market::ML::TSNEPipeline;

use strict;
use warnings;
use Carp qw(croak);
use File::Basename qw(dirname);
use File::Path qw(make_path);

use Market::ML::FeatureSchema;
use Market::ML::StandardScaler;
use Market::ML::TSNE;

sub new {
    my ($class, %args) = @_;
    return bless {
        perplexity    => $args{perplexity} // 30,
        max_iter      => $args{max_iter} // 750,
        random_state  => $args{random_state} // 42,
        verbose       => $args{verbose} // 1,
        learning_rate => $args{learning_rate} // 'auto',
    }, $class;
}

sub run {
    my ($self, %args) = @_;
    my $rows = $args{rows} // [];
    croak "rows debe ser ARRAY y no puede estar vacío\n"
        if ref($rows) ne 'ARRAY' || !@$rows;

    my $output_file = $args{output_file}
        // croak "Debe indicar output_file\n";

    my $features = Market::ML::FeatureSchema->select_feature_columns(
        rows => $rows,
    );

    my $scaler = Market::ML::StandardScaler->new(
        feature_columns => $features,
    );
    my $vectors = $scaler->fit_transform(rows => $rows);

    my $n_samples = scalar(@$vectors);
    my $perplexity = $self->{perplexity};
    $perplexity = int(($n_samples - 1) / 3)
        if $perplexity >= $n_samples;
    $perplexity = 1 if $perplexity < 1;

    my $tsne = Market::ML::TSNE->new(
        n_components  => 2,
        perplexity    => $perplexity,
        init          => 'random',
        random_state  => $self->{random_state},
        max_iter      => $self->{max_iter},
        learning_rate => $self->{learning_rate},
        verbose       => $self->{verbose},
        method        => 'exact',
        metric        => 'euclidean',
        n_iter_check  => 25,
    );

    my $coords = $tsne->fit_transform($vectors);

    _export_projection(
        file => $output_file,
        rows => $rows,
        coordinates => $coords,
        seed        => $self->{random_state},
        perplexity  => $perplexity,
        iterations => $self->{max_iter},
    );

    return {
        output_file                => $output_file,
        samples                    => $n_samples,
        original_features          => scalar(@$features),
        numeric_features           => $scaler->numeric_feature_count,
        categorical_features       => $scaler->categorical_feature_count,
        tensor_dimensions          => scalar(@{$scaler->output_features}),
        perplexity                 => $perplexity,
        max_iter                   => $self->{max_iter},
        random_state               => $self->{random_state},
        kl_divergence              => $tsne->{kl_divergence_},
        iterations_completed       => defined($tsne->{n_iter_}) ? $tsne->{n_iter_} + 1 : undef,
        feature_columns            => $features,
        tensor_feature_columns     => $scaler->output_features,
    };
}

sub _export_projection {
    my (%args) = @_;
    my $file = $args{file};
    my $rows = $args{rows};
    my $coords = $args{coordinates};
    my $seed = $args{seed};
    my $perplexity = $args{perplexity};
    my $iterations = $args{iterations};

    my $dir = dirname($file);
    make_path($dir) if $dir ne '.' && !-d $dir;
    open my $fh, '>:encoding(UTF-8)', $file
        or croak "No se puede escribir '$file': $!\n";

    my @columns = qw(
        tsne_x tsne_y tsne_seed tsne_perplexity tsne_iterations
        target dataset_date source_file symbol timeframe
        pivot_id pivot_timestamp confirmation_timestamp
        pivot_index confirmation_index confirmation_delay pivot_side
        structure_type structure_mode source candle_direction
        pivot_price pivot_volume atr_14 range_atr_ratio body_atr_ratio
        volume_ratio_20 volume_zscore_20
        previous_pivot_type distance_previous_pivot bars_previous_pivot swing_size_atr
        liquidity_type last_structure_event last_structure_event_direction
        bars_since_structure_event distance_last_structure_event_atr
        bos_count_previous_20 choch_count_previous_20
        near_equal_level equal_level_type distance_equal_level_atr bars_since_equal_level
        inside_fvg nearest_fvg_type distance_fvg_atr fvg_size_atr bars_since_fvg
        fvg_mitigated active_fvg_count_50
        inside_order_block nearest_ob_type distance_ob_atr ob_size_atr bars_since_ob
        ob_invalidated active_ob_count_50
        active_bsl_count active_ssl_count distance_nearest_bsl_atr
        distance_nearest_ssl_atr liquidity_imbalance_100
    );
    print {$fh} join(',', @columns), "\n";

    for my $i (0 .. $#$rows) {
        my $row = $rows->[$i];
        my ($x, $y) = @{$coords->[$i]};
        my %out = (
            tsne_x                 => $x,
            tsne_y                 => $y,
            tsne_seed              => $seed,
            tsne_perplexity        => $perplexity,
            tsne_iterations        => $iterations,
            target                 => $row->{target},
            dataset_date           => $row->{dataset_date},
            source_file            => $row->{source_file},
            pivot_id               => $row->{pivot_id},
            pivot_timestamp        => $row->{pivot_timestamp},
            confirmation_timestamp => $row->{confirmation_timestamp},
            pivot_index            => $row->{pivot_index},
            confirmation_index     => $row->{confirmation_index},
            pivot_side             => $row->{pivot_side},
        );

        # Conserva metadatos y variables estructurales para la exploración web.
        # Las coordenadas t-SNE siguen siendo únicamente tsne_x y tsne_y.
        for my $column (@columns) {
            next if exists $out{$column};
            $out{$column} = $row->{$column};
        }
        print {$fh} join(',', map { _csv_escape($out{$_}) } @columns), "\n";
    }
    close $fh or croak "No se pudo cerrar '$file': $!\n";
}

sub _csv_escape {
    my ($value) = @_;
    $value = '' if !defined $value;
    $value = "$value";
    if ($value =~ /[",\r\n]/) {
        $value =~ s/"/""/g;
        return qq{"$value"};
    }
    return $value;
}

1;
