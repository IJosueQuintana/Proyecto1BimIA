package Market::ML::SequentialGMMTrainer;

use strict;
use warnings;
use Carp qw(croak);
use List::Util qw(sum);
use Market::ML::StandardScaler;
use Market::ML::GaussianMixtureModel;
use Market::ML::SequentialFeatureSchema;

sub new {
    my ($class, %args) = @_;
    return bless {
        components      => $args{components} // 4,
        max_iterations  => $args{max_iterations} // 100,
        tolerance       => $args{tolerance} // 1e-5,
        regularization  => $args{regularization} // 1e-4,
        seed            => $args{seed} // 42,
        label_column    => $args{label_column} // 'state_label',
        feature_columns => $args{feature_columns} // Market::ML::SequentialFeatureSchema->feature_columns,
        scaler          => undef,
        model           => undef,
        cluster_map     => {},
        fitted          => 0,
    }, $class;
}

sub fit {
    my ($self, %args) = @_;
    my $rows = $args{rows} // [];
    croak "rows debe ser ARRAY\n" if ref($rows) ne 'ARRAY';
    croak "No se puede entrenar GMM con cero filas\n" if !@$rows;

    Market::ML::SequentialFeatureSchema->validate_feature_columns(
        columns => $self->{feature_columns}
    );

    my $scaler = Market::ML::StandardScaler->new(
        feature_columns => $self->{feature_columns}
    );
    my $vectors = $scaler->fit_transform(rows => $rows);

    my $model = Market::ML::GaussianMixtureModel->new(
        components     => $self->{components},
        max_iterations => $self->{max_iterations},
        tolerance      => $self->{tolerance},
        regularization => $self->{regularization},
        seed           => $self->{seed},
    );
    $model->fit(vectors => $vectors);

    my $clusters = $model->predict_components(vectors => $vectors);
    my %counts;
    for my $i (0 .. $#$clusters) {
        my $label = uc($rows->[$i]{$self->{label_column}} // '');
        next if $label eq '';
        $counts{$clusters->[$i]}{$label}++;
    }

    my %map;
    for my $cluster (0 .. $self->{components} - 1) {
        my $bucket = $counts{$cluster} // {};
        my ($label) = sort {
            ($bucket->{$b} // 0) <=> ($bucket->{$a} // 0) || $a cmp $b
        } keys %$bucket;
        $map{$cluster} = defined($label) ? $label : 'IDLE';
    }

    $self->{scaler} = $scaler;
    $self->{model} = $model;
    $self->{cluster_map} = \%map;
    $self->{fitted} = 1;
    return $self;
}

sub predict_clusters {
    my ($self, %args) = @_;
    _require_fitted($self);
    my $rows = $args{rows} // [];
    my $vectors = $self->{scaler}->transform(rows => $rows);
    return $self->{model}->predict_components(vectors => $vectors);
}

sub predict_labels {
    my ($self, %args) = @_;
    my $clusters = $self->predict_clusters(%args);
    return [map { $self->{cluster_map}{$_} // 'IDLE' } @$clusters];
}

sub transform {
    my ($self, %args) = @_;
    _require_fitted($self);
    return $self->{scaler}->transform(rows => ($args{rows} // []));
}

sub summary {
    my ($self) = @_;
    _require_fitted($self);
    return {
        components     => $self->{model}->components,
        converged      => $self->{model}->converged,
        iterations     => $self->{model}->iterations,
        log_likelihood => $self->{model}->log_likelihood,
        cluster_map    => {%{$self->{cluster_map}}},
        feature_count  => scalar(@{$self->{feature_columns}}),
    };
}

sub model { _require_fitted($_[0]); return $_[0]{model}; }
sub scaler { _require_fitted($_[0]); return $_[0]{scaler}; }
sub cluster_map { _require_fitted($_[0]); return {%{$_[0]{cluster_map}}}; }
sub feature_columns { return [@{$_[0]{feature_columns}}]; }

sub _require_fitted {
    my ($self) = @_;
    croak "SequentialGMMTrainer todavía no fue entrenado\n" if !$self->{fitted};
}

1;
