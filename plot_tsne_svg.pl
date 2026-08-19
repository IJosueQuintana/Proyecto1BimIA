use strict;
use warnings;
use FindBin;
use File::Basename qw(dirname);
use File::Path qw(make_path);

my $input = shift(@ARGV) // "$FindBin::Bin/datasets/ml_pipeline/tsne_development_projection.csv";
my $output = shift(@ARGV) // "$FindBin::Bin/datasets/ml_pipeline/tsne_development_projection.svg";

die "No existe el archivo de proyección: $input\nEjecute primero: perl tsne_pipeline.pl\n" if !-f $input;

my $rows = read_csv_hashes($input);
die "La proyección no contiene filas\n" if !@$rows;

my @points;
my (%counts, %seeds, %perplexities, %iterations);
for my $row (@$rows) {
    next if !defined($row->{tsne_x}) || !defined($row->{tsne_y});
    next if $row->{tsne_x} eq '' || $row->{tsne_y} eq '';
    my $target = defined($row->{target}) && $row->{target} ne '' ? $row->{target} : 'SIN_CLASE';
    push @points, {
        x => 0 + $row->{tsne_x},
        y => 0 + $row->{tsne_y},
        target => $target,
    };
    $counts{$target}++;
    $seeds{$row->{tsne_seed}}++ if defined($row->{tsne_seed}) && $row->{tsne_seed} ne '';
    $perplexities{$row->{tsne_perplexity}}++ if defined($row->{tsne_perplexity}) && $row->{tsne_perplexity} ne '';
    $iterations{$row->{tsne_iterations}}++ if defined($row->{tsne_iterations}) && $row->{tsne_iterations} ne '';
}
die "No se encontraron coordenadas válidas\n" if !@points;

my ($min_x, $max_x, $min_y, $max_y) = ($points[0]{x}, $points[0]{x}, $points[0]{y}, $points[0]{y});
for my $p (@points) {
    $min_x = $p->{x} if $p->{x} < $min_x;
    $max_x = $p->{x} if $p->{x} > $max_x;
    $min_y = $p->{y} if $p->{y} < $min_y;
    $max_y = $p->{y} if $p->{y} > $max_y;
}
my $range_x = $max_x - $min_x; $range_x = 1 if $range_x == 0;
my $range_y = $max_y - $min_y; $range_y = 1 if $range_y == 0;

my ($width, $height) = (1200, 800);
my ($left, $right, $top, $bottom) = (90, 260, 85, 80);
my $plot_w = $width - $left - $right;
my $plot_h = $height - $top - $bottom;

my %colors = (
    RUN => '#2563eb',
    GRAB => '#f59e0b',
    SWEEP => '#dc2626',
    SIN_CLASE => '#6b7280',
);
my @fallback = ('#16a34a', '#9333ea', '#0891b2', '#db2777', '#4b5563');
my $fallback_i = 0;
for my $target (sort keys %counts) {
    $colors{$target} //= $fallback[$fallback_i++ % @fallback];
}

my $dir = dirname($output);
make_path($dir) if $dir ne '.' && !-d $dir;
open my $fh, '>:encoding(UTF-8)', $output or die "No se puede escribir '$output': $!\n";

my $seed = join('/', sort keys %seeds); $seed = 'N/D' if $seed eq '';
my $perplexity = join('/', sort keys %perplexities); $perplexity = 'N/D' if $perplexity eq '';
my $iters = join('/', sort keys %iterations); $iters = 'N/D' if $iters eq '';

print {$fh} qq{<svg xmlns="http://www.w3.org/2000/svg" width="$width" height="$height" viewBox="0 0 $width $height">\n};
print {$fh} qq{<rect width="100%" height="100%" fill="#ffffff"/>\n};
print {$fh} qq{<text x="$left" y="38" font-family="Arial, sans-serif" font-size="24" font-weight="bold" fill="#111827">Proyección t-SNE — TRAIN + VALIDATION</text>\n};
print {$fh} qq{<text x="$left" y="64" font-family="Arial, sans-serif" font-size="14" fill="#4b5563">Semilla: $seed · Perplexity: $perplexity · Iteraciones: $iters · Muestras: } . scalar(@points) . qq{</text>\n};
print {$fh} qq{<rect x="$left" y="$top" width="$plot_w" height="$plot_h" fill="#f9fafb" stroke="#d1d5db"/>\n};

for my $p (@points) {
    my $cx = $left + (($p->{x} - $min_x) / $range_x) * $plot_w;
    my $cy = $top + $plot_h - (($p->{y} - $min_y) / $range_y) * $plot_h;
    my $color = $colors{$p->{target}};
    print {$fh} sprintf qq{<circle cx="%.3f" cy="%.3f" r="4.2" fill="%s" fill-opacity="0.72" stroke="#ffffff" stroke-width="0.6"/>\n}, $cx, $cy, $color;
}

print {$fh} qq{<text x="} . ($left + $plot_w/2) . qq{" y="} . ($height - 25) . qq{" text-anchor="middle" font-family="Arial, sans-serif" font-size="15" fill="#374151">t-SNE 1</text>\n};
print {$fh} qq{<text x="25" y="} . ($top + $plot_h/2) . qq{" text-anchor="middle" transform="rotate(-90 25 } . ($top + $plot_h/2) . qq{)" font-family="Arial, sans-serif" font-size="15" fill="#374151">t-SNE 2</text>\n};

my $legend_x = $left + $plot_w + 35;
my $legend_y = $top + 20;
print {$fh} qq{<text x="$legend_x" y="$legend_y" font-family="Arial, sans-serif" font-size="17" font-weight="bold" fill="#111827">Estados</text>\n};
my $idx = 0;
for my $target (sort keys %counts) {
    my $y = $legend_y + 32 + $idx * 30;
    print {$fh} qq{<circle cx="$legend_x" cy="$y" r="6" fill="$colors{$target}"/>\n};
    print {$fh} qq{<text x="} . ($legend_x + 16) . qq{" y="} . ($y + 5) . qq{" font-family="Arial, sans-serif" font-size="14" fill="#374151">$target ($counts{$target})</text>\n};
    $idx++;
}
print {$fh} qq{<text x="$legend_x" y="} . ($legend_y + 32 + $idx*30 + 25) . qq{" font-family="Arial, sans-serif" font-size="12" fill="#6b7280">Uso exploratorio:</text>\n};
print {$fh} qq{<text x="$legend_x" y="} . ($legend_y + 32 + $idx*30 + 43) . qq{" font-family="Arial, sans-serif" font-size="12" fill="#6b7280">no reemplaza las features</text>\n};
print {$fh} qq{<text x="$legend_x" y="} . ($legend_y + 32 + $idx*30 + 59) . qq{" font-family="Arial, sans-serif" font-size="12" fill="#6b7280">originales para GMM/HMM.</text>\n};
print {$fh} "</svg>\n";
close $fh or die "No se pudo cerrar '$output': $!\n";

print "Gráfico t-SNE generado correctamente:\n$output\n";
print "Distribución: " . join(', ', map { "$_=$counts{$_}" } sort keys %counts) . "\n";

sub read_csv_hashes {
    my ($file) = @_;
    open my $fh, '<:encoding(UTF-8)', $file or die "No se puede leer '$file': $!\n";
    my $header_line = <$fh>;
    die "CSV sin cabecera: $file\n" if !defined $header_line;
    $header_line =~ s/[\r\n]+$//;
    my @headers = parse_csv_line($header_line);
    my @data;
    while (my $line = <$fh>) {
        $line =~ s/[\r\n]+$//;
        next if $line eq '';
        my @values = parse_csv_line($line);
        my %row;
        @row{@headers} = @values;
        push @data, \%row;
    }
    close $fh;
    return \@data;
}

sub parse_csv_line {
    my ($line) = @_;
    my (@fields, $field, $quoted) = ((), '', 0);
    my @chars = split //, $line;
    for (my $i = 0; $i < @chars; $i++) {
        my $ch = $chars[$i];
        if ($quoted) {
            if ($ch eq '"') {
                if ($i + 1 < @chars && $chars[$i + 1] eq '"') { $field .= '"'; $i++; }
                else { $quoted = 0; }
            } else { $field .= $ch; }
        } else {
            if ($ch eq '"') { $quoted = 1; }
            elsif ($ch eq ',') { push @fields, $field; $field = ''; }
            else { $field .= $ch; }
        }
    }
    push @fields, $field;
    return @fields;
}
