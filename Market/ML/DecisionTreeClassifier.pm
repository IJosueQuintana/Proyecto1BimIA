package Market::ML::DecisionTreeClassifier;

use strict;
use warnings;
use List::Util qw(sum);
use Market::ML::FeatureSchema;

sub new {
    my ($class, %args) = @_;
    return bless {
        max_depth        => $args{max_depth}        // 3,
        min_samples_split=> $args{min_samples_split}// 10,
        min_samples_leaf => $args{min_samples_leaf} // 5,
        min_gain         => $args{min_gain}         // 1e-9,
        labels           => $args{labels}           // [qw(RUN GRAB SWEEP)],
        feature_columns  => $args{feature_columns},
        root             => undef,
        feature_importance_raw => {},
        node_count       => 0,
        depth_reached    => 0,
    }, $class;
}

sub default_excluded_columns {
    return Market::ML::FeatureSchema->excluded_columns;
}

sub select_feature_columns {
    my ($class, %args) = @_;
    return Market::ML::FeatureSchema->select_feature_columns(%args);
}

sub fit {
    my ($self, %args) = @_;
    my $rows = $args{rows} // [];
    die "rows debe ser ARRAY\n" if ref($rows) ne 'ARRAY';
    die "No se puede entrenar el árbol con cero filas\n" if !@$rows;

    my $features = $self->{feature_columns};
    $features = __PACKAGE__->select_feature_columns(rows => $rows)
        if ref($features) ne 'ARRAY' || !@$features;
    Market::ML::FeatureSchema->validate_feature_columns(columns => $features);
    $self->{feature_columns} = [@$features];

    $self->{feature_importance_raw} = {};
    $self->{node_count} = 0;
    $self->{depth_reached} = 0;
    $self->{root} = $self->_build_node($rows, 0);
    return $self;
}

sub predict {
    my ($self, %args) = @_;
    my $rows = $args{rows} // [];
    die "El árbol todavía no fue entrenado\n" if !$self->{root};
    return [ map { $self->_predict_one($_, $self->{root}) } @$rows ];
}

sub node_count    { return $_[0]{node_count}; }
sub depth_reached { return $_[0]{depth_reached}; }
sub feature_columns { return [ @{$_[0]{feature_columns} // []} ]; }

sub feature_importances {
    my ($self) = @_;
    my $raw = $self->{feature_importance_raw};
    my $total = sum(values %$raw) || 0;
    return {} if $total <= 0;
    return { map { $_ => $raw->{$_} / $total } keys %$raw };
}

sub _build_node {
    my ($self, $rows, $depth) = @_;
    $self->{node_count}++;
    $self->{depth_reached} = $depth if $depth > $self->{depth_reached};

    my ($majority, $counts) = $self->_majority($rows);
    my $node = {
        prediction => $majority,
        counts     => $counts,
        samples    => scalar(@$rows),
        depth      => $depth,
        leaf       => 1,
    };

    my $nonzero_classes = scalar grep { ($counts->{$_} // 0) > 0 } @{$self->{labels}};
    return $node if $nonzero_classes <= 1;
    return $node if $depth >= $self->{max_depth};
    return $node if @$rows < $self->{min_samples_split};

    my $parent_gini = $self->_gini($rows);
    my $best = $self->_best_split($rows, $parent_gini);
    return $node if !$best || $best->{gain} <= $self->{min_gain};

    $node->{leaf}       = 0;
    $node->{feature}    = $best->{feature};
    $node->{split_type} = $best->{split_type};
    $node->{threshold}  = $best->{threshold} if $best->{split_type} eq 'numeric';
    $node->{category}   = $best->{category}  if $best->{split_type} eq 'categorical';
    $node->{gain}       = $best->{gain};

    $self->{feature_importance_raw}{$best->{feature}} += $best->{gain} * scalar(@$rows);
    $node->{left}  = $self->_build_node($best->{left},  $depth + 1);
    $node->{right} = $self->_build_node($best->{right}, $depth + 1);
    return $node;
}

sub _best_split {
    my ($self, $rows, $parent_gini) = @_;
    my $n = scalar(@$rows);
    my $best;

    FEATURE:
    for my $feature (@{$self->{feature_columns}}) {
        my @values = map { defined($_->{$feature}) ? "$_->{$feature}" : '' } @$rows;
        my $numeric = 1;
        for my $v (@values) {
            next if $v eq '';
            if ($v !~ /^[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?$/) {
                $numeric = 0;
                last;
            }
        }

        if ($numeric) {
            my %seen;
            my @unique = sort { $a <=> $b } grep { !$seen{$_}++ } map { 0 + $_ } grep { $_ ne '' } @values;
            next FEATURE if @unique < 2;
            for my $i (0 .. $#unique - 1) {
                my $threshold = ($unique[$i] + $unique[$i + 1]) / 2;
                my (@left, @right);
                for my $row (@$rows) {
                    my $v = defined($row->{$feature}) && $row->{$feature} ne '' ? 0 + $row->{$feature} : 0;
                    push @{ $v <= $threshold ? \@left : \@right }, $row;
                }
                next if @left < $self->{min_samples_leaf} || @right < $self->{min_samples_leaf};
                my $weighted = (@left / $n) * $self->_gini(\@left)
                             + (@right / $n) * $self->_gini(\@right);
                my $gain = $parent_gini - $weighted;
                $best = {
                    feature => $feature, split_type => 'numeric', threshold => $threshold,
                    gain => $gain, left => \@left, right => \@right,
                } if _better_split($best, $gain, $feature, $threshold);
            }
        }
        else {
            my %seen;
            my @categories = sort grep { !$seen{$_}++ } @values;
            next FEATURE if @categories < 2;
            for my $category (@categories) {
                my (@left, @right);
                for my $row (@$rows) {
                    my $v = defined($row->{$feature}) ? "$row->{$feature}" : '';
                    push @{ $v eq $category ? \@left : \@right }, $row;
                }
                next if @left < $self->{min_samples_leaf} || @right < $self->{min_samples_leaf};
                my $weighted = (@left / $n) * $self->_gini(\@left)
                             + (@right / $n) * $self->_gini(\@right);
                my $gain = $parent_gini - $weighted;
                $best = {
                    feature => $feature, split_type => 'categorical', category => $category,
                    gain => $gain, left => \@left, right => \@right,
                } if _better_split($best, $gain, $feature, $category);
            }
        }
    }
    return $best;
}

sub _better_split {
    my ($best, $gain, $feature, $value) = @_;
    return 1 if !$best;
    return 1 if $gain > $best->{gain} + 1e-12;
    return 0 if $gain < $best->{gain} - 1e-12;
    my $old_key = $best->{feature} . '|' . ($best->{threshold} // $best->{category} // '');
    my $new_key = $feature . '|' . $value;
    return $new_key lt $old_key;
}

sub _predict_one {
    my ($self, $row, $node) = @_;
    return $node->{prediction} if $node->{leaf};
    my $go_left;
    if ($node->{split_type} eq 'numeric') {
        my $v = defined($row->{$node->{feature}}) && $row->{$node->{feature}} ne ''
            ? 0 + $row->{$node->{feature}} : 0;
        $go_left = $v <= $node->{threshold};
    }
    else {
        my $v = defined($row->{$node->{feature}}) ? "$row->{$node->{feature}}" : '';
        $go_left = $v eq $node->{category};
    }
    return $self->_predict_one($row, $go_left ? $node->{left} : $node->{right});
}

sub _majority {
    my ($self, $rows) = @_;
    my %counts = map { $_ => 0 } @{$self->{labels}};
    $counts{uc($_->{target} // '')}++ for @$rows;
    my $best = $self->{labels}[0];
    for my $label (@{$self->{labels}}) {
        $best = $label if $counts{$label} > $counts{$best};
    }
    return ($best, \%counts);
}

sub _gini {
    my ($self, $rows) = @_;
    return 0 if !@$rows;
    my (undef, $counts) = $self->_majority($rows);
    my $n = scalar(@$rows);
    my $sum_sq = 0;
    $sum_sq += (($counts->{$_} // 0) / $n) ** 2 for @{$self->{labels}};
    return 1 - $sum_sq;
}

1;
