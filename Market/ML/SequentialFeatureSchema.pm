package Market::ML::SequentialFeatureSchema;

use strict;
use warnings;
use Carp qw(croak);

sub metadata_columns { return [qw(dataset_date source_file symbol timeframe candle_index timestamp epoch)]; }
sub state_columns    { return [qw(state_label)]; }
sub target_columns   { return [qw(event_target outcome_target)]; }
sub feature_columns  { return [qw(
    return_1 return_3 return_5
    range_atr body_atr upper_wick_atr lower_wick_atr close_position
    volatility_10 volatility_20 volume_zscore volume_ratio
    slope_10 slope_20 price_vs_mean_20_atr
    distance_to_bsl_atr distance_to_ssl_atr
    active_bsl_count active_ssl_count liquidity_imbalance
    inside_fvg distance_fvg_atr inside_order_block distance_ob_atr
    bars_since_structure_event last_structure_event
)]; }

sub all_columns {
    my ($class) = @_;
    return [@{$class->metadata_columns}, @{$class->feature_columns}, @{$class->state_columns}, @{$class->target_columns}];
}

sub excluded_columns {
    my ($class) = @_;
    return { map { $_ => 1 } (@{$class->metadata_columns}, @{$class->state_columns}, @{$class->target_columns}) };
}

sub validate_feature_columns {
    my ($class, %args) = @_;
    my $columns = $args{columns} // [];
    croak "columns debe ser ARRAY\n" if ref($columns) ne 'ARRAY';
    my $excluded = $class->excluded_columns;
    my @bad = grep { $excluded->{$_} } @$columns;
    croak "Columnas no causales dentro de features: " . join(', ', @bad) . "\n" if @bad;
    return 1;
}

sub describe {
    my ($class) = @_;
    return {
        observation_unit => 'CANDLE',
        metadata_columns => $class->metadata_columns,
        feature_columns  => $class->feature_columns,
        state_columns    => $class->state_columns,
        target_columns   => $class->target_columns,
        feature_count    => scalar(@{$class->feature_columns}),
    };
}

1;
