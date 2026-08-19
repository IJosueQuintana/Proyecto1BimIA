package Market::ML::TSNE::TSNE;

use strict;
use warnings;
use Carp qw(croak);

use Market::ML::TSNE::DistanceEngine;
use Market::ML::TSNE::Perplexity;
use Market::ML::TSNE::ProbabilityMatrix;
use Market::ML::TSNE::Optimizer;

sub new {
    my ($class, %args) = @_;
    return bless {
        n_components      => $args{n_components} // 2,
        perplexity        => $args{perplexity} // 30,
        max_iter          => $args{max_iter} // 750,
        learning_rate     => $args{learning_rate} // 'auto',
        random_state      => $args{random_state} // 42,
        verbose           => $args{verbose} // 0,
        n_iter_check      => $args{n_iter_check} // 25,
        early_exaggeration=> $args{early_exaggeration} // 12.0,
        early_iter        => $args{early_iter} // 250,
        kl_divergence_    => undef,
        n_iter_           => undef,
    }, $class;
}

sub fit_transform {
    my ($self, $vectors) = @_;
    croak "fit_transform requiere un ARRAY de vectores\n"
        if ref($vectors) ne 'ARRAY' || !@$vectors;
    my $n = scalar @$vectors;
    croak "perplexity debe ser menor que el número de muestras\n"
        if $self->{perplexity} >= $n;

    print "[t-SNE] Calculando distancias cuadráticas por pares...\n" if $self->{verbose};
    my $distances = Market::ML::TSNE::DistanceEngine->pairwise_squared($vectors);

    print "[t-SNE] Ajustando probabilidades para perplexity=$self->{perplexity}...\n"
        if $self->{verbose};
    my $conditional = Market::ML::TSNE::Perplexity->conditional_probabilities(
        distances  => $distances,
        perplexity => $self->{perplexity},
    );
    my $p = Market::ML::TSNE::ProbabilityMatrix->symmetric_joint(
        conditional => $conditional->{probabilities},
    );

    my $learning_rate = $self->{learning_rate};
    if (!defined($learning_rate) || $learning_rate eq 'auto') {
        $learning_rate = $n / ($self->{early_exaggeration} * 4.0);
        $learning_rate = 50.0 if $learning_rate < 50.0;
    }

    print "[t-SNE] Iniciando optimización exacta (learning_rate=$learning_rate)...\n"
        if $self->{verbose};
    my $result = Market::ML::TSNE::Optimizer->optimize(
        probabilities      => $p,
        n_components       => $self->{n_components},
        max_iter           => $self->{max_iter},
        learning_rate      => $learning_rate,
        random_state       => $self->{random_state},
        verbose            => $self->{verbose},
        check_every        => $self->{n_iter_check},
        early_exaggeration => $self->{early_exaggeration},
        early_iter         => $self->{early_iter},
    );

    $self->{kl_divergence_} = $result->{kl_divergence};
    $self->{n_iter_} = $result->{iterations} - 1;
    return $result->{embedding};
}

1;
