package Market::ML::FinalGhostFeatureSchema;

use strict;
use warnings;
use Carp qw(croak);

sub target_columns { return [qw(target_trace_3 target_trace_5 target_trace_10 target_trace_15)]; }

sub metadata_columns {
    return [qw(
        dataset_date source_file symbol timeframe
        ghost_id ghost_index ghost_timestamp ghost_price_mid ghost_definition
        pivot_id pivot_index confirmation_index pivot_timestamp confirmation_timestamp
        legacy_liquidity_target liquidity_state swept_index resolved_index
        source
    )];
}

sub excluded_columns {
    my ($class) = @_;
    return { map { $_ => 1 } (@{$class->metadata_columns}, @{$class->target_columns}) };
}

sub select_feature_columns {
    my ($class, %args) = @_;
    my $rows = $args{rows} // [];
    croak "rows debe ser ARRAY y no puede estar vacio\n" if ref($rows) ne 'ARRAY' || !@$rows;
    croak "Cada fila debe ser HASH\n" if ref($rows->[0]) ne 'HASH';
    my $excluded = $class->excluded_columns;

    # Evitamos niveles absolutos de precio y columnas auxiliares que no generalizan
    # bien entre meses. Conservamos distancias, razones, estructura y contexto causal.
    my %absolute_price = map { $_ => 1 } qw(
        pivot_open pivot_high pivot_low pivot_close pivot_price
        confirm_open confirm_high confirm_low confirm_close
        previous_pivot_price
    );

    my @features = sort grep {
        !$excluded->{$_}
        && !$absolute_price{$_}
        && $_ !~ /^target_/
        && $_ !~ /timestamp$/
        && $_ !~ /_index$/
    } keys %{$rows->[0]};

    croak "No se encontraron features finales\n" if !@features;
    return \@features;
}

1;
