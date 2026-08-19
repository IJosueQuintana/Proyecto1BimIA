package Market::ML::FeatureSchema;

use strict;
use warnings;
use Carp qw(croak);

# Contrato central de columnas para todos los modelos del proyecto.
# La selección se hace a partir de las columnas realmente presentes en el
# dataset, pero nunca permite metadatos, etiquetas ni resultados conocidos
# únicamente después del instante de confirmación.

sub target_column { return 'target'; }

sub metadata_columns {
    return [qw(
        dataset_date source_file pivot_id symbol timeframe
        pivot_index confirmation_index pivot_timestamp confirmation_timestamp
        source
    )];
}

sub forbidden_future_columns {
    return [qw(
        target liquidity_state swept_index resolved_index
    )];
}

sub excluded_columns {
    my ($class, %args) = @_;

    my %excluded = map { $_ => 1 } (
        @{$class->metadata_columns},
        @{$class->forbidden_future_columns},
    );

    if (ref($args{extra}) eq 'ARRAY') {
        $excluded{$_} = 1 for @{$args{extra}};
    }

    return \%excluded;
}

sub select_feature_columns {
    my ($class, %args) = @_;
    my $rows = $args{rows} // [];

    croak "rows debe ser ARRAY\n" if ref($rows) ne 'ARRAY';
    return [] if !@$rows;
    croak "Cada fila debe ser un HASH\n" if ref($rows->[0]) ne 'HASH';

    my $excluded = $class->excluded_columns(extra => $args{exclude});
    my @columns = sort grep { !$excluded->{$_} } keys %{$rows->[0]};

    $class->validate_feature_columns(columns => \@columns);
    return \@columns;
}

sub validate_feature_columns {
    my ($class, %args) = @_;
    my $columns = $args{columns} // [];

    croak "columns debe ser ARRAY\n" if ref($columns) ne 'ARRAY';

    my $forbidden = $class->excluded_columns;
    my @invalid = sort grep { $forbidden->{$_} } @$columns;

    croak "Columnas prohibidas dentro del conjunto de features: "
        . join(', ', @invalid) . "\n"
        if @invalid;

    my %seen;
    my @duplicates = sort grep { $seen{$_}++ } @$columns;
    croak "Columnas de features duplicadas: " . join(', ', @duplicates) . "\n"
        if @duplicates;

    return 1;
}

sub describe {
    my ($class, %args) = @_;
    my $features = $args{feature_columns} // [];
    $class->validate_feature_columns(columns => $features);

    return {
        target_column           => $class->target_column,
        metadata_columns        => $class->metadata_columns,
        forbidden_future_columns=> $class->forbidden_future_columns,
        feature_columns         => [@$features],
        feature_count           => scalar(@$features),
    };
}

1;
