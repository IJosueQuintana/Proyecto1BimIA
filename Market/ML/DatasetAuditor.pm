package Market::ML::DatasetAuditor;

use strict;
use warnings;
use Carp qw(croak);
use File::Path qw(make_path);
use List::Util qw(sum min max);
use POSIX qw(floor);

sub new {
    my ($class, %args) = @_;
    return bless {
        labels => $args{labels} // [qw(RUN GRAB SWEEP)],
        near_zero_unique_ratio => $args{near_zero_unique_ratio} // 0.01,
        high_corr_threshold => $args{high_corr_threshold} // 0.90,
    }, $class;
}

sub read_csv {
    my ($self, $file) = @_;
    croak "No existe CSV: $file\n" if !-f $file;
    open my $fh, '<:encoding(UTF-8)', $file or croak "No se puede abrir '$file': $!\n";
    my $header_line = <$fh>;
    croak "CSV vacío: $file\n" if !defined $header_line;
    chomp $header_line; $header_line =~ s/\r$//;
    my @columns = _parse_csv_line($header_line);
    my @rows;
    my $line_no = 1;
    while (my $line = <$fh>) {
        $line_no++;
        chomp $line; $line =~ s/\r$//;
        next if $line eq '';
        my @values = _parse_csv_line($line);
        my %row;
        for my $i (0 .. $#columns) { $row{$columns[$i]} = defined $values[$i] ? $values[$i] : ''; }
        $row{_audit_source_file} = $file;
        $row{_audit_line} = $line_no;
        push @rows, \%row;
    }
    close $fh;
    return { columns => \@columns, rows => \@rows };
}

sub audit {
    my ($self, %args) = @_;
    my $train = $args{train} // croak "Falta train\n";
    my $validation = $args{validation} // croak "Falta validation\n";
    my $output_dir = $args{output_dir} // croak "Falta output_dir\n";
    make_path($output_dir) if !-d $output_dir;

    my @rows;
    for my $r (@{$train->{rows}}) { my %c = %$r; $c{audit_split} = 'TRAIN'; push @rows, \%c; }
    for my $r (@{$validation->{rows}}) { my %c = %$r; $c{audit_split} = 'VALIDATION'; push @rows, \%c; }
    my @columns = @{$train->{columns}};
    my %seen_col = map { $_ => 1 } @columns;
    push @columns, grep { !$seen_col{$_}++ } @{$validation->{columns}};

    my ($numeric, $categorical) = _infer_types(\@rows, \@columns);
    my $stats = _feature_statistics(\@rows, $numeric, $categorical);
    my $duplicates = _duplicates(\@rows, \@columns);
    my $label_stats = _label_statistics(\@rows, $self->{labels});
    my $transitions = _label_transitions(\@rows, $self->{labels});
    my $correlations = _pairwise_matrix(\@rows, $numeric, 'correlation');
    my $covariances = _pairwise_matrix(\@rows, $numeric, 'covariance');
    my $signals = _feature_signal(\@rows, $numeric, $categorical, $self->{labels});
    my $outliers = _outliers(\@rows, $numeric);
    my $suspicious = _suspicious_rows(\@rows);
    my $session = _session_distribution(\@rows, $self->{labels});

    _write_csv("$output_dir/dataset_quality.csv", [qw(metric value detail)], _quality_rows(\@rows, \@columns, $numeric, $categorical, $duplicates, $stats));
    _write_csv("$output_dir/feature_statistics.csv", [qw(feature type count missing missing_ratio unique unique_ratio min max mean median variance stddev cv skewness kurtosis constant near_constant)], $stats);
    _write_csv("$output_dir/feature_correlations.csv", [qw(feature_a feature_b n correlation abs_correlation high_correlation)], $correlations);
    _write_csv("$output_dir/feature_covariance.csv", [qw(feature_a feature_b n covariance)], $covariances);
    _write_csv("$output_dir/feature_signal.csv", [qw(feature type n eta_squared mutual_information note)], $signals);
    _write_csv("$output_dir/duplicate_rows.csv", [qw(duplicate_type key count split source_file timestamp pivot_index confirmation_index target lines)], $duplicates);
    _write_csv("$output_dir/label_statistics.csv", [qw(label count ratio split)], $label_stats);
    _write_csv("$output_dir/label_transitions.csv", [qw(from_label to_label count probability)], $transitions);
    _write_csv("$output_dir/session_distribution.csv", [qw(split session label count ratio)], $session);
    _write_csv("$output_dir/outliers.csv", [qw(split source_file line timestamp pivot_index confirmation_index target feature value q1 q3 iqr lower_bound upper_bound)], $outliers);
    _write_csv("$output_dir/suspicious_rows.csv", [qw(split source_file line timestamp pivot_index confirmation_index target issue detail)], $suspicious);
    _write_markdown_report("$output_dir/AUDIT_REPORT.md", {
        rows => \@rows, columns => \@columns, numeric => $numeric, categorical => $categorical,
        stats => $stats, duplicates => $duplicates, transitions => $transitions,
        signals => $signals, suspicious => $suspicious, correlations => $correlations,
        labels => $self->{labels}, high_corr_threshold => $self->{high_corr_threshold},
    });

    return {
        output_dir => $output_dir,
        rows => scalar(@rows), numeric => scalar(@$numeric), categorical => scalar(@$categorical),
        duplicates => scalar(@$duplicates), suspicious => scalar(@$suspicious),
    };
}

sub _infer_types {
    my ($rows, $columns) = @_;
    my %metadata = map { $_ => 1 } qw(target audit_split _audit_source_file _audit_line symbol pivot_timestamp confirmation_timestamp source structure_type structure_mode pivot_side candle_direction previous_pivot_type liquidity_type liquidity_state last_structure_event last_structure_event_direction equal_level_type nearest_fvg_type nearest_ob_type);
    my (@num, @cat);
    for my $c (@$columns) {
        next if $c =~ /^_/ || $c eq 'target';
        my ($nonempty, $numeric) = (0, 0);
        for my $r (@$rows) {
            my $v = $r->{$c}; next if !defined($v) || $v eq '';
            $nonempty++; $numeric++ if _is_number($v);
        }
        if (!$metadata{$c} && $nonempty > 0 && $numeric == $nonempty) { push @num, $c; }
        else { push @cat, $c; }
    }
    return (\@num, \@cat);
}

sub _feature_statistics {
    my ($rows, $numeric, $categorical) = @_;
    my @out;
    for my $feature (@$numeric) {
        my @v = map { 0 + $_->{$feature} } grep { defined($_->{$feature}) && $_->{$feature} ne '' && _is_number($_->{$feature}) } @$rows;
        my $n = scalar @v; my $missing = scalar(@$rows) - $n;
        my %u = map { ("$_", 1) } @v; my $unique = scalar keys %u;
        my ($minv,$maxv,$mean,$median,$var,$sd,$cv,$skew,$kurt) = ('','','','','','','','','');
        if ($n) {
            @v = sort { $a <=> $b } @v; $minv=$v[0]; $maxv=$v[-1]; $mean=sum(@v)/$n; $median=_quantile(\@v,0.5);
            $var = $n > 1 ? sum(map { ($_-$mean)**2 } @v)/($n-1) : 0; $sd=sqrt($var); $cv=abs($mean)>1e-12 ? $sd/abs($mean) : '';
            if ($sd > 0 && $n > 2) { $skew=sum(map { (($_-$mean)/$sd)**3 } @v)/$n; $kurt=sum(map { (($_-$mean)/$sd)**4 } @v)/$n - 3; }
        }
        push @out, { feature=>$feature,type=>'numeric',count=>$n,missing=>$missing,missing_ratio=>@$rows?$missing/@$rows:0,unique=>$unique,unique_ratio=>$n?$unique/$n:0,min=>$minv,max=>$maxv,mean=>$mean,median=>$median,variance=>$var,stddev=>$sd,cv=>$cv,skewness=>$skew,kurtosis=>$kurt,constant=>($unique<=1?1:0),near_constant=>($n && $unique/$n<=0.01?1:0) };
    }
    for my $feature (@$categorical) {
        my @v = map { $_->{$feature} } grep { defined($_->{$feature}) && $_->{$feature} ne '' } @$rows;
        my %u; $u{$_}++ for @v; my $n=@v; my $missing=@$rows-$n; my $unique=keys %u;
        my $dominant=0; for my $count (values %u) { $dominant=$count if $count>$dominant; }
        push @out, { feature=>$feature,type=>'categorical',count=>$n,missing=>$missing,missing_ratio=>@$rows?$missing/@$rows:0,unique=>$unique,unique_ratio=>$n?$unique/$n:0,min=>'',max=>'',mean=>'',median=>'',variance=>'',stddev=>'',cv=>'',skewness=>'',kurtosis=>'',constant=>($unique<=1?1:0),near_constant=>($n && $dominant/$n>=0.99?1:0) };
    }
    return \@out;
}

sub _duplicates {
    my ($rows, $columns) = @_;
    my (%causal,%full);
    my @feature_cols = grep { $_ ne 'target' && $_ !~ /^(?:resolved_index|swept_index)$/ } @$columns;
    for my $r (@$rows) {
        my $source = _source($r); my $key = join('|', $source, map { $r->{$_}//'' } qw(symbol timeframe pivot_index confirmation_index));
        push @{$causal{$key}}, $r;
        my $fkey=join("\x1f",map{$r->{$_}//''}@feature_cols); push @{$full{$fkey}},$r;
    }
    my @out;
    for my $spec (['CAUSAL_KEY',\%causal],['FEATURE_VECTOR',\%full]) {
        my ($type,$h)=@$spec;
        for my $key (keys %$h) { next if @{$h->{$key}}<2; my $first=$h->{$key}[0]; push @out,{duplicate_type=>$type,key=>$type eq 'CAUSAL_KEY'?$key:'HASHED_VECTOR',count=>scalar(@{$h->{$key}}),split=>$first->{audit_split}//'',source_file=>_source($first),timestamp=>_timestamp($first),pivot_index=>$first->{pivot_index}//'',confirmation_index=>$first->{confirmation_index}//'',target=>$first->{target}//'',lines=>join(';',map{$_->{_audit_line}//''}@{$h->{$key}})}; }
    }
    return \@out;
}

sub _label_statistics {
    my ($rows, $labels) = @_;
    my %allowed = map { ($_ => 1) } @$labels;
    my @out;

    for my $split ('TRAIN', 'VALIDATION', 'ALL') {
        my @set = $split eq 'ALL'
            ? @$rows
            : grep { ($_->{audit_split} // '') eq $split } @$rows;
        my $n = scalar @set;
        my %count;
        $count{uc($_->{target} // 'NONE')}++ for @set;

        for my $label (@$labels) {
            my $value = $count{$label} // 0;
            push @out, {
                label => $label,
                count => $value,
                ratio => $n ? $value / $n : 0,
                split => $split,
            };
        }

        my $other = 0;
        for my $label (keys %count) {
            $other += $count{$label} if !$allowed{$label};
        }
        push @out, {
            label => 'OTHER',
            count => $other,
            ratio => $n ? $other / $n : 0,
            split => $split,
        };
    }

    return \@out;
}

sub _label_transitions {
    my ($rows,$labels)=@_; my @sorted=sort{(_session($a) cmp _session($b)) || (_order($a)<=>_order($b))}@$rows; my (%count,%total); my $prev;
    for my $r (@sorted){if($prev && _session($prev) eq _session($r)){my $a=uc($prev->{target}//'NONE');my $b=uc($r->{target}//'NONE');$count{"$a\x1f$b"}++;$total{$a}++;}$prev=$r;}
    my @out; for my $k(sort keys%count){my($a,$b)=split/\x1f/,$k;push@out,{from_label=>$a,to_label=>$b,count=>$count{$k},probability=>$total{$a}?$count{$k}/$total{$a}:0};} return \@out;
}

sub _pairwise_matrix {
    my ($rows,$features,$kind)=@_; my @out;
    for my $i(0..$#$features){for my $j($i..$#$features){my($a,$b)=($features->[$i],$features->[$j]);my(@x,@y);for my$r(@$rows){next if !_is_number($r->{$a})||!_is_number($r->{$b});push@x,0+$r->{$a};push@y,0+$r->{$b};}next if @x<2;my$mx=sum(@x)/@x;my$my=sum(@y)/@y;my$cov=sum(map{($x[$_]-$mx)*($y[$_]-$my)}0..$#x)/(@x-1);if($kind eq 'covariance'){push@out,{feature_a=>$a,feature_b=>$b,n=>scalar(@x),covariance=>$cov};}else{my$vx=sum(map{($_-$mx)**2}@x)/(@x-1);my$vy=sum(map{($_-$my)**2}@y)/(@y-1);my$c=($vx>0&&$vy>0)?$cov/sqrt($vx*$vy):0;push@out,{feature_a=>$a,feature_b=>$b,n=>scalar(@x),correlation=>$c,abs_correlation=>abs($c),high_correlation=>($i!=$j&&abs($c)>=0.90?1:0)};}}}return\@out;
}

sub _feature_signal {
    my($rows,$numeric,$categorical,$labels)=@_;my@out;
    for my$f(@$numeric){my@valid=grep{_is_number($_->{$f})&&defined($_->{target})&&$_->{target} ne ''}@$rows;my$n=@valid;my$eta='';if($n>1){my$mean=sum(map{0+$_->{$f}}@valid)/$n;my($between,$total)=(0,0);$total+=((0+$_->{$f})-$mean)**2 for@valid;for my$l(@$labels){my@v=map{0+$_->{$f}}grep{uc($_->{target}//'')eq$l}@valid;next if!@v;my$m=sum(@v)/@v;$between+=@v*($m-$mean)**2;}$eta=$total>0?$between/$total:0;}my$mi=_numeric_mi(\@valid,$f,$labels);push@out,{feature=>$f,type=>'numeric',n=>$n,eta_squared=>$eta,mutual_information=>$mi,note=>'MI con discretización por cuartiles'};}
    for my$f(@$categorical){next if$f eq'target';my@valid=grep{defined($_->{$f})&&$_->{$f} ne ''&&defined($_->{target})&&$_->{target} ne ''}@$rows;my$mi=_discrete_mi(\@valid,sub{$_[0]->{$f}},sub{uc($_[0]->{target}//'NONE')});push@out,{feature=>$f,type=>'categorical',n=>scalar(@valid),eta_squared=>'',mutual_information=>$mi,note=>'MI discreta'};}return\@out;
}

sub _numeric_mi { my($rows,$f,$labels)=@_;return 0 if@$rows<4;my@v=sort{$a<=>$b}map{0+$_->{$f}}@$rows;my($q1,$q2,$q3)=map{_quantile(\@v,$_)}(0.25,0.5,0.75);return _discrete_mi($rows,sub{my$x=0+$_[0]->{$f};$x<=$q1?'Q1':$x<=$q2?'Q2':$x<=$q3?'Q3':'Q4'},sub{uc($_[0]->{target}//'NONE')}); }
sub _discrete_mi { my($rows,$fx,$fy)=@_;my$n=@$rows;return 0 if!$n;my(%x,%y,%xy);for my$r(@$rows){my$a=$fx->($r);my$b=$fy->($r);$x{$a}++;$y{$b}++;$xy{"$a\x1f$b"}++;}my$mi=0;for my$k(keys%xy){my($a,$b)=split/\x1f/,$k;my$pxy=$xy{$k}/$n;my$px=$x{$a}/$n;my$py=$y{$b}/$n;$mi+=$pxy*log($pxy/($px*$py)) if$pxy&&$px&&$py;}return$mi; }

sub _outliers { my($rows,$features)=@_;my@out;for my$f(@$features){my@v=sort{$a<=>$b}map{0+$_->{$f}}grep{_is_number($_->{$f})}@$rows;next if@v<4;my$q1=_quantile(\@v,.25);my$q3=_quantile(\@v,.75);my$iqr=$q3-$q1;next if$iqr<=0;my($lo,$hi)=($q1-1.5*$iqr,$q3+1.5*$iqr);for my$r(@$rows){next if!_is_number($r->{$f});my$x=0+$r->{$f};next if$x>=$lo&&$x<=$hi;push@out,{split=>$r->{audit_split}//'',source_file=>_source($r),line=>$r->{_audit_line}//'',timestamp=>_timestamp($r),pivot_index=>$r->{pivot_index}//'',confirmation_index=>$r->{confirmation_index}//'',target=>$r->{target}//'',feature=>$f,value=>$x,q1=>$q1,q3=>$q3,iqr=>$iqr,lower_bound=>$lo,upper_bound=>$hi};}}return\@out; }

sub _suspicious_rows { my($rows)=@_;my@out;for my$r(@$rows){my@issues;if(_is_number($r->{pivot_index})&&_is_number($r->{confirmation_index})&&$r->{confirmation_index}<$r->{pivot_index}){push@issues,['CONFIRMATION_BEFORE_PIVOT','confirmation_index menor que pivot_index'];}if(defined$r->{pivot_timestamp}&&defined$r->{confirmation_timestamp}&&$r->{pivot_timestamp} ne ''&&$r->{confirmation_timestamp} ne ''&&$r->{confirmation_timestamp} lt $r->{pivot_timestamp}){push@issues,['TIMESTAMP_REVERSED','confirmation_timestamp anterior a pivot_timestamp'];}if(!_is_number($r->{atr_14})||$r->{atr_14}<=0){push@issues,['INVALID_ATR','ATR ausente, no numérico o <= 0'];}if(!grep{uc($r->{target}//'')eq$_}qw(RUN GRAB SWEEP)){push@issues,['INVALID_TARGET','target fuera de RUN/GRAB/SWEEP'];}if(_is_number($r->{confirmation_delay})&&_is_number($r->{confirmation_index})&&_is_number($r->{pivot_index})&&$r->{confirmation_delay}!=($r->{confirmation_index}-$r->{pivot_index})){push@issues,['DELAY_MISMATCH','confirmation_delay no coincide con índices'];}for my$i(@issues){push@out,{split=>$r->{audit_split}//'',source_file=>_source($r),line=>$r->{_audit_line}//'',timestamp=>_timestamp($r),pivot_index=>$r->{pivot_index}//'',confirmation_index=>$r->{confirmation_index}//'',target=>$r->{target}//'',issue=>$i->[0],detail=>$i->[1]};}}return\@out; }

sub _session_distribution { my($rows,$labels)=@_;my(%c,%t);for my$r(@$rows){my$s=_session($r);my$sp=$r->{audit_split}//'';my$l=uc($r->{target}//'NONE');$c{"$sp\x1f$s\x1f$l"}++;$t{"$sp\x1f$s"}++;}my@out;for my$k(sort keys%c){my($sp,$s,$l)=split/\x1f/,$k;push@out,{split=>$sp,session=>$s,label=>$l,count=>$c{$k},ratio=>$t{"$sp\x1f$s"}?$c{$k}/$t{"$sp\x1f$s"}:0};}return\@out; }

sub _quality_rows { my($rows,$columns,$numeric,$categorical,$duplicates,$stats)=@_;my$missing=sum(map{$_->{missing}}@$stats);my$constant=sum(map{$_->{constant}}@$stats);my$near=sum(map{$_->{near_constant}}@$stats);return[{metric=>'rows',value=>scalar(@$rows),detail=>'TRAIN + VALIDATION; TEST no auditado'},{metric=>'columns',value=>scalar(@$columns),detail=>'Columnas originales'},{metric=>'numeric_features',value=>scalar(@$numeric),detail=>''},{metric=>'categorical_features',value=>scalar(@$categorical),detail=>''},{metric=>'missing_cells',value=>$missing||0,detail=>''},{metric=>'duplicate_groups',value=>scalar(@$duplicates),detail=>'Grupos, no filas individuales'},{metric=>'constant_features',value=>$constant||0,detail=>''},{metric=>'near_constant_features',value=>$near||0,detail=>''},{metric=>'rows_per_numeric_feature',value=>@$numeric?scalar(@$rows)/scalar(@$numeric):'',detail=>'Indicador simple de dimensionalidad'}]; }

sub _write_markdown_report {
    my ($file, $d) = @_;
    open my $fh, '>:encoding(UTF-8)', $file
        or croak "No se puede escribir $file: $!\n";

    my $row_count = scalar @{$d->{rows}};
    my @constant = grep { $_->{constant} } @{$d->{stats}};
    my @near_constant = grep { $_->{near_constant} && !$_->{constant} } @{$d->{stats}};
    my @high_corr = grep { $_->{high_correlation} } @{$d->{correlations}};
    my @signals = sort {
        ($b->{mutual_information} // 0) <=> ($a->{mutual_information} // 0)
    } @{$d->{signals}};

    print {$fh} "# Auditoría profunda del dataset ML\n\n";
    print {$fh} "La auditoría utiliza **TRAIN + VALIDATION**. El conjunto **TEST permanece reservado y no fue leído**.\n\n";
    print {$fh} "## Resumen\n\n";
    print {$fh} "- Filas auditadas: **$row_count**\n";
    print {$fh} "- Variables numéricas: **" . scalar(@{$d->{numeric}}) . "**\n";
    print {$fh} "- Variables categóricas: **" . scalar(@{$d->{categorical}}) . "**\n";
    print {$fh} "- Grupos duplicados: **" . scalar(@{$d->{duplicates}}) . "**\n";
    print {$fh} "- Filas/alertas sospechosas: **" . scalar(@{$d->{suspicious}}) . "**\n";
    print {$fh} "- Variables constantes: **" . scalar(@constant) . "**\n";
    print {$fh} "- Variables casi constantes: **" . scalar(@near_constant) . "**\n";
    print {$fh} "- Pares con |r| >= $d->{high_corr_threshold}: **" . scalar(@high_corr) . "**\n\n";

    print {$fh} "## Relación observaciones/dimensionalidad\n\n";
    print {$fh} "Se auditan $row_count filas frente a " . scalar(@{$d->{numeric}}) . " variables numéricas. Una relación baja implica estimaciones de medias, varianzas, GMM y emisiones HMM potencialmente inestables.\n\n";

    print {$fh} "## Variables constantes\n\n";
    print {$fh} @constant
        ? join("\n", map { "- `" . $_->{feature} . "`" } @constant) . "\n\n"
        : "Ninguna.\n\n";

    print {$fh} "## Variables casi constantes\n\n";
    print {$fh} @near_constant
        ? join("\n", map { "- `" . $_->{feature} . "`" } @near_constant) . "\n\n"
        : "Ninguna.\n\n";

    print {$fh} "## Correlaciones altas\n\n";
    if (@high_corr) {
        my $last = $#high_corr < 19 ? $#high_corr : 19;
        for my $r (@high_corr[0 .. $last]) {
            printf {$fh} "- `%s` ↔ `%s`: r=%.4f\n",
                $r->{feature_a}, $r->{feature_b}, $r->{correlation};
        }
    }
    else {
        print {$fh} "No se detectaron pares sobre el umbral.\n";
    }

    print {$fh} "\n## Variables con mayor información mutua respecto al target\n\n";
    if (@signals) {
        my $last = $#signals < 14 ? $#signals : 14;
        for my $r (@signals[0 .. $last]) {
            printf {$fh} "- `%s` (%s): MI=%.6f",
                $r->{feature}, $r->{type}, $r->{mutual_information} // 0;
            printf {$fh} ", eta²=%.6f", $r->{eta_squared}
                if defined($r->{eta_squared}) && $r->{eta_squared} ne '';
            print {$fh} "\n";
        }
    }

    print {$fh} <<'MD';

## Interpretación requerida

1. Verificar manualmente en el gráfico las filas de `suspicious_rows.csv` y una muestra de cada etiqueta.
2. Revisar si las variables con mayor señal se calculan completamente en `confirmation_index` o si describen un evento ya resuelto.
3. Revisar `label_transitions.csv`: transiciones casi uniformes indican que RUN/GRAB/SWEEP no forman buenos estados Markovianos.
4. Revisar `session_distribution.csv`: diferencias fuertes por sesión indican cambio de régimen o sesgo por fecha.
5. No eliminar variables ni cambiar etiquetas hasta revisar estos reportes.
MD

    close $fh;
}

sub _write_csv { my($file,$columns,$rows)=@_;open my$fh,'>:encoding(UTF-8)',$file or croak"No se puede escribir '$file': $!\n";print$fh join(',',map{_csv_escape($_)}@$columns),"\n";for my$r(@$rows){print$fh join(',',map{_csv_escape(defined$r->{$_}?$r->{$_}:'')}@$columns),"\n";}close$fh; }
sub _csv_escape { my($v)=@_;$v=''if!defined$v;$v="$v";if($v=~/[",\r\n]/){$v=~s/"/""/g;return qq{"$v"};}return$v; }
sub _parse_csv_line { my($line)=@_; my @f; my $cur=''; my $q=0;my@c=split//,$line;for(my$i=0;$i<@c;$i++){my$ch=$c[$i];if($q){if($ch eq '"'){if($i+1<@c&&$c[$i+1] eq '"'){$cur.='"';$i++;}else{$q=0;}}else{$cur.=$ch;}}else{if($ch eq '"'){$q=1;}elsif($ch eq ','){push@f,$cur;$cur='';}else{$cur.=$ch;}}}push@f,$cur;return@f; }
sub _is_number { defined($_[0]) && $_[0] ne '' && $_[0] =~ /^[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?$/ }
sub _quantile { my($v,$p)=@_;return''if!@$v;return$v->[0]if@$v==1;my$pos=$p*($#$v);my$lo=floor($pos);my$hi=$lo+1;return$v->[$lo]if$hi>$#$v;my$w=$pos-$lo;return$v->[$lo]*(1-$w)+$v->[$hi]*$w; }
sub _source { my($r)=@_;return$r->{source_file}//$r->{dataset_date}//$r->{source}//$r->{_audit_source_file}//''; }
sub _timestamp { my($r)=@_;return$r->{confirmation_timestamp}//$r->{pivot_timestamp}//''; }
sub _session { my($r)=@_;my$s=_source($r);$s=~s{.*[/\\]}{};return($r->{audit_split}//'').'|'.$s; }
sub _order { my($r)=@_;return 0+$r->{confirmation_index} if _is_number($r->{confirmation_index});return 0+$r->{pivot_index} if _is_number($r->{pivot_index});return 0; }

1;
