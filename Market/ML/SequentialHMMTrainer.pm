package Market::ML::SequentialHMMTrainer;

use strict;
use warnings;
use Carp qw(croak);
use Market::ML::StandardScaler;
use Market::ML::HiddenMarkovModel;
use Market::ML::SequentialFeatureSchema;

sub new {
    my ($class, %args) = @_;
    return bless {
        states          => $args{states} // [qw(IDLE APPROACH INTERACTION EXPANSION)],
        smoothing       => defined($args{smoothing}) ? $args{smoothing} : 1.0,
        variance_floor  => defined($args{variance_floor}) ? $args{variance_floor} : 1e-2,
        label_column    => $args{label_column} // 'state_label',
        feature_columns => $args{feature_columns} // Market::ML::SequentialFeatureSchema->feature_columns,
        scaler          => undef,
        model           => undef,
        fitted          => 0,
    }, $class;
}

sub fit {
    my ($self, %args) = @_;
    my $rows = $args{rows} // [];
    my $sequence_ids = $args{sequence_ids};
    croak "rows debe ser ARRAY\n" if ref($rows) ne 'ARRAY';
    croak "No se puede entrenar HMM con cero filas\n" if !@$rows;
    croak "sequence_ids debe ser ARRAY y coincidir con rows\n"
        if ref($sequence_ids) ne 'ARRAY' || @$sequence_ids != @$rows;

    my $labels = [map { uc($_->{$self->{label_column}} // '') } @$rows];
    my $scaler = Market::ML::StandardScaler->new(
        feature_columns => $self->{feature_columns}
    );
    my $vectors = $scaler->fit_transform(rows => $rows);

    my $model = Market::ML::HiddenMarkovModel->new(
        states         => $self->{states},
        smoothing      => $self->{smoothing},
        variance_floor => $self->{variance_floor},
    );
    $model->fit(
        vectors      => $vectors,
        labels       => $labels,
        sequence_ids => $sequence_ids,
    );

    $self->{scaler} = $scaler;
    $self->{model} = $model;
    $self->{fitted} = 1;
    return $self;
}

sub predict_online {
    my ($self, %args) = @_;
    _require_fitted($self);
    my $rows = $args{rows} // [];
    my $sequence_ids = $args{sequence_ids};
    my $vectors = $self->{scaler}->transform(rows => $rows);
    return $self->{model}->predict_online(
        vectors => $vectors,
        sequence_ids => $sequence_ids,
    );
}

sub viterbi {
    my ($self, %args) = @_;
    _require_fitted($self);
    my $rows = $args{rows} // [];
    my $sequence_ids = $args{sequence_ids};
    my $vectors = $self->{scaler}->transform(rows => $rows);
    return $self->{model}->viterbi(
        vectors => $vectors,
        sequence_ids => $sequence_ids,
    );
}

sub score {
    my ($self, %args) = @_;
    _require_fitted($self);
    my $rows = $args{rows} // [];
    my $sequence_ids = $args{sequence_ids};
    my $vectors = $self->{scaler}->transform(rows => $rows);
    return $self->{model}->score(vectors => $vectors, sequence_ids => $sequence_ids);
}

sub summary {
    my ($self) = @_;
    _require_fitted($self);
    return {
        states               => $self->{model}->states,
        dimensions           => $self->{model}->dimensions,
        train_log_likelihood => $self->{model}->train_log_likelihood,
        initial              => $self->{model}->initial_probabilities,
        transition           => $self->{model}->transition_matrix,
        state_counts         => $self->{model}->state_counts,
        feature_count        => scalar(@{$self->{feature_columns}}),
    };
}

sub model { _require_fitted($_[0]); return $_[0]{model}; }
sub scaler { _require_fitted($_[0]); return $_[0]{scaler}; }
sub feature_columns { return [@{$_[0]{feature_columns}}]; }

sub _require_fitted {
    my ($self) = @_;
    croak "SequentialHMMTrainer todavía no fue entrenado\n" if !$self->{fitted};
}

1;
