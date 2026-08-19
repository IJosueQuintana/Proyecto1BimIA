use strict;
use warnings;
use utf8;
use FindBin;
use File::Basename qw(dirname);
use File::Path qw(make_path);
use File::Spec;

my $no_open = grep { $_ eq '--no-open' } @ARGV;
@ARGV = grep { $_ ne '--no-open' } @ARGV;
my $input = shift(@ARGV)
    // "$FindBin::Bin/datasets/ml_pipeline/tsne_development_projection.csv";
my $output = shift(@ARGV)
    // "$FindBin::Bin/Visualization/tsne_interactive.html";

make_path("$FindBin::Bin/Visualization") if !-d "$FindBin::Bin/Visualization";
die "No existe la proyección: $input\nEjecute primero: perl tsne_pipeline.pl\n" if !-f $input;

my ($rows, $columns) = read_csv_hashes($input);
die "La proyección no contiene filas.\n" if !@$rows;

my @points;
my (%seeds, %perplexities, %iterations);
for my $row (@$rows) {
    next if !defined($row->{tsne_x}) || !defined($row->{tsne_y});
    next if $row->{tsne_x} eq '' || $row->{tsne_y} eq '';

    my %point = %$row;
    $point{x} = 0 + $row->{tsne_x};
    $point{y} = 0 + $row->{tsne_y};
    $point{target} = value_or($row->{target}, 'SIN_CLASE');
    $point{source_file} = value_or($row->{source_file}, 'SIN_ARCHIVO');
    $point{pivot_side} = value_or($row->{pivot_side}, 'SIN_LADO');
    $point{dataset_date} = value_or($row->{dataset_date}, 'SIN_FECHA');
    push @points, \%point;

    $seeds{$row->{tsne_seed}}++ if value_or($row->{tsne_seed}, '') ne '';
    $perplexities{$row->{tsne_perplexity}}++ if value_or($row->{tsne_perplexity}, '') ne '';
    $iterations{$row->{tsne_iterations}}++ if value_or($row->{tsne_iterations}, '') ne '';
}
die "No se encontraron coordenadas válidas.\n" if !@points;

my @color_candidates = grep {
    my $name = $_;
    $name !~ /^tsne_/ && $name !~ /^(?:pivot_id|pivot_index|confirmation_index|pivot_timestamp|confirmation_timestamp)$/
        && scalar(unique_nonempty(\@points, $name)) > 1
        && scalar(unique_nonempty(\@points, $name)) <= 20
} qw(target source_file dataset_date pivot_side structure_type structure_mode candle_direction liquidity_type last_structure_event last_structure_event_direction near_equal_level equal_level_type inside_fvg nearest_fvg_type fvg_mitigated inside_order_block nearest_ob_type ob_invalidated);
@color_candidates = ('target') if !@color_candidates;

my $seed = join('/', sort keys %seeds) || 'N/D';
my $perplexity = join('/', sort keys %perplexities) || 'N/D';
my $iters = join('/', sort keys %iterations) || 'N/D';
my $json_points = json_encode(\@points);
my $json_columns = json_encode($columns);
my $json_colors = json_encode(\@color_candidates);

my $out_dir = dirname($output);
make_path($out_dir) if !-d $out_dir;
open my $fh, '>:encoding(UTF-8)', $output or die "No se puede escribir '$output': $!\n";
print {$fh} <<'HTML';
<!doctype html>
<html lang="es">
<head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Explorador t-SNE — IAAA</title>
<script src="https://cdn.plot.ly/plotly-2.35.2.min.js"></script>
<style>
:root{color-scheme:dark;--bg:#090f1d;--panel:#111a2d;--panel2:#17233b;--text:#edf2fb;--muted:#9aa9bf;--line:#2b3a58;--accent:#60a5fa}
*{box-sizing:border-box}body{margin:0;font-family:Inter,Segoe UI,Arial,sans-serif;background:var(--bg);color:var(--text);overflow:hidden}
header{height:74px;padding:15px 20px 10px;border-bottom:1px solid var(--line);background:#0d1527;display:flex;align-items:center;justify-content:space-between;gap:16px}
h1{margin:0 0 5px;font-size:22px}.meta{color:var(--muted);font-size:12px;display:flex;flex-wrap:wrap;gap:13px}.header-actions{display:flex;gap:8px}
.shell{display:grid;grid-template-columns:270px minmax(0,1fr) 0;transition:grid-template-columns .2s;height:calc(100vh - 74px)}
.shell.details-open{grid-template-columns:270px minmax(0,1fr) 330px}.shell.sidebar-closed{grid-template-columns:0 minmax(0,1fr) 0}.shell.sidebar-closed.details-open{grid-template-columns:0 minmax(0,1fr) 330px}
aside,.details{overflow:auto;background:var(--panel);transition:opacity .2s}.filters{padding:14px;border-right:1px solid var(--line)}.sidebar-closed .filters{opacity:0;pointer-events:none;padding:0}
.details{border-left:1px solid var(--line);opacity:0;pointer-events:none;padding:0}.details-open .details{opacity:1;pointer-events:auto;padding:14px}
main{min-width:0;min-height:0;padding:4px 6px 6px;position:relative}#plot{width:100%;height:100%}
.section{margin-bottom:15px}.section-title{font-weight:700;margin-bottom:7px;font-size:11px;text-transform:uppercase;letter-spacing:.07em;color:#cbd5e1}
select,input[type=text],input[type=range]{width:100%;padding:8px;border-radius:7px;border:1px solid var(--line);background:var(--panel2);color:var(--text)}input[type=range]{padding:0}
button{border:1px solid var(--line);border-radius:7px;padding:8px 10px;background:#1d4ed8;color:#fff;font-weight:700;cursor:pointer}button.secondary{background:var(--panel2)}button.compact{width:auto;margin:0}
.filters button{width:100%;margin-top:7px}.stats{display:grid;grid-template-columns:1fr 1fr;gap:7px}.stat{background:var(--panel2);padding:8px;border-radius:7px}.stat b{display:block;font-size:17px}.stat span{color:var(--muted);font-size:10px}
.legend-list{display:flex;flex-direction:column;gap:5px}.legend-item{display:flex;align-items:center;justify-content:space-between;font-size:12px;padding:5px 7px;background:var(--panel2);border-radius:6px}.dot{width:9px;height:9px;border-radius:50%;display:inline-block;margin-right:7px}
.detail-row{padding:7px 0;border-bottom:1px solid #22314c}.detail-row b{display:block;color:#a9bad1;font-size:10px;text-transform:uppercase;letter-spacing:.05em}.detail-row span{font-size:13px;word-break:break-word}.empty{color:var(--muted);font-size:13px;line-height:1.5}.small-label{display:block;color:var(--muted);font-size:10px;margin-bottom:4px}.range-label{font-size:10px;color:#cbd5e1;margin-top:7px;line-height:1.35}.toggle-row{display:flex;align-items:center;gap:8px;font-size:12px;padding:4px 0}.toggle-row input{width:auto}
.floating{position:absolute;z-index:4;top:10px;left:12px}.offline{display:none;margin:10px;padding:10px;border:1px solid #ef4444;background:#451a1a;border-radius:8px}
@media(max-width:900px){body{overflow:auto}.shell,.shell.details-open{grid-template-columns:1fr;height:auto}.filters,.details{border:0}.details{display:none}main{height:72vh}}
</style></head><body>
HTML
print {$fh} qq{<header><div><h1>Explorador interactivo t-SNE</h1><div class="meta"><span>TRAIN + VALIDATION: } . scalar(@points) . qq{ muestras</span><span>Semilla: $seed</span><span>Perplexity: $perplexity</span><span>Iteraciones: $iters</span><span>TEST FINAL no utilizado</span></div></div><div class="header-actions"><button id="toggleSidebar" class="secondary compact">Ocultar filtros</button><button id="downloadBtn" class="compact">Descargar PNG</button></div></header>\n};
print {$fh} <<'HTML';
<div id="offline" class="offline">No se pudo cargar Plotly. Verifique la conexión a internet.</div>
<div id="shell" class="shell">
<aside class="filters">
<div class="section"><div class="section-title">Resumen visible</div><div class="stats"><div class="stat"><b id="visibleCount">0</b><span>Visibles</span></div><div class="stat"><b id="totalCount">0</b><span>Total</span></div><div class="stat"><b id="groupCount">0</b><span>Grupos</span></div><div class="stat"><b id="dominantGroup">—</b><span>Grupo dominante</span></div></div></div>
<div class="section"><div class="section-title">Colorear por</div><select id="colorBy"></select></div>
<div class="section"><div class="section-title">Leyenda / grupos</div><div id="groupFilters" class="legend-list"></div></div>
<div class="section"><div class="section-title">Archivo fuente</div><select id="sourceFilter"><option value="ALL">Todos</option></select></div>
<div class="section"><div class="section-title">Tipo de pivote</div><select id="sideFilter"><option value="ALL">Todos</option></select></div>
<div class="section"><div class="section-title">Sesión / dataset</div><select id="datasetFilter"><option value="ALL">Todos</option></select></div>
<div class="section"><div class="section-title">Buscar pivot_id</div><input id="pivotSearch" type="text" placeholder="Ejemplo: 145"></div>
<div class="section"><div class="section-title">Rango temporal</div><div style="display:grid;grid-template-columns:1fr 1fr;gap:7px"><div><span class="small-label">Desde</span><input id="timeFrom" type="range" min="0" max="0" value="0"></div><div><span class="small-label">Hasta</span><input id="timeTo" type="range" min="0" max="0" value="0"></div></div><div id="timeLabel" class="range-label">Todas las fechas</div></div>
<div class="section"><div class="section-title">Capas analíticas</div><label class="toggle-row"><input id="densityToggle" type="checkbox"> Mostrar densidad</label><label class="toggle-row"><input id="neighborsToggle" type="checkbox" checked> Mostrar vecinos al seleccionar</label><div style="margin-top:7px"><span class="small-label">Vecinos k: <b id="kValue">10</b></span><input id="kRange" type="range" min="3" max="30" value="10"></div></div>
<div class="section"><div class="section-title">Tamaño: <span id="sizeValue">6</span></div><input id="sizeRange" type="range" min="3" max="18" value="6"></div>
<div class="section"><div class="section-title">Opacidad: <span id="opacityValue">0.60</span></div><input id="opacityRange" type="range" min="20" max="100" value="60"></div>
<button id="fitBtn" class="secondary">Ajustar vista a datos</button>
<button id="resetBtn" class="secondary">Restablecer filtros</button>
</aside>
<main><button id="openSidebar" class="secondary compact floating" style="display:none">Mostrar filtros</button><div id="plot"></div></main>
<aside class="details"><div style="display:flex;justify-content:space-between;align-items:center"><div class="section-title">Detalle del punto</div><button id="closeDetails" class="secondary compact">×</button></div><div id="detailContent" class="empty">Haz clic sobre un punto para revisar sus variables.</div></aside>
</div><script>
HTML
print {$fh} "const POINTS=$json_points;\nconst COLUMNS=$json_columns;\nconst COLOR_FIELDS=$json_colors;\n";
print {$fh} <<'JS';
const LABELS={target:'Estado objetivo',source_file:'Archivo fuente',dataset_date:'Dataset',pivot_side:'Tipo de pivote',structure_type:'Estructura',structure_mode:'Modo estructural',candle_direction:'Dirección vela',liquidity_type:'Liquidez',last_structure_event:'Último evento estructural',last_structure_event_direction:'Dirección del evento',near_equal_level:'Cerca de nivel igual',equal_level_type:'Tipo de nivel igual',inside_fvg:'Dentro de FVG',nearest_fvg_type:'FVG cercano',fvg_mitigated:'FVG mitigado',inside_order_block:'Dentro de OB',nearest_ob_type:'OB cercano',ob_invalidated:'OB invalidado'};
const TARGET_COLORS={RUN:'#22c55e',GRAB:'#3b82f6',SWEEP:'#ef4444',SIN_CLASE:'#94a3b8'};
const PALETTE=['#22c55e','#3b82f6','#ef4444','#f59e0b','#a855f7','#06b6d4','#ec4899','#f97316','#84cc16','#14b8a6','#8b5cf6','#eab308','#64748b','#f43f5e','#0ea5e9','#d946ef','#10b981','#fb7185','#38bdf8','#c084fc'];
const shell=document.getElementById('shell');let activeGroups=new Set();let colorMap={};let selectedPoint=null;let selectedNeighbors=[];const TIMES=[...new Set(POINTS.map(p=>val(p,'confirmation_timestamp')!=='SIN_DATO'?val(p,'confirmation_timestamp'):val(p,'pivot_timestamp')).filter(v=>v!=='SIN_DATO'))].sort();
document.getElementById('totalCount').textContent=POINTS.length;
initTimeRange();
fillSelect('sourceFilter',unique('source_file'));fillSelect('sideFilter',unique('pivot_side'));fillSelect('datasetFilter',unique('dataset_date'));
COLOR_FIELDS.forEach(f=>{const o=document.createElement('option');o.value=f;o.textContent=LABELS[f]||f;document.getElementById('colorBy').appendChild(o)});
function val(p,f){const v=p[f];return v===undefined||v===null||String(v)===''?'SIN_DATO':String(v)}
function unique(f){return [...new Set(POINTS.map(p=>val(p,f)))].sort((a,b)=>a.localeCompare(b,undefined,{numeric:true}))}
function fillSelect(id,values){const el=document.getElementById(id);values.forEach(v=>{const o=document.createElement('option');o.value=v;o.textContent=v;el.appendChild(o)})}
function assignColors(groups,field){colorMap={};groups.forEach((g,i)=>colorMap[g]=(field==='target'&&TARGET_COLORS[g])||PALETTE[i%PALETTE.length])}
function rebuildGroups(){const field=document.getElementById('colorBy').value;const groups=unique(field);activeGroups=new Set(groups);assignColors(groups,field);const box=document.getElementById('groupFilters');box.innerHTML='';groups.forEach(g=>{const row=document.createElement('label');row.className='legend-item';const count=POINTS.filter(p=>val(p,field)===g).length;row.innerHTML=`<span><span class="dot" style="background:${colorMap[g]}"></span>${esc(g)}</span><span>${count}</span><input type="checkbox" data-group="${escAttr(g)}" checked>`;box.appendChild(row)});box.querySelectorAll('[data-group]').forEach(x=>x.addEventListener('change',()=>{x.checked?activeGroups.add(x.dataset.group):activeGroups.delete(x.dataset.group);render()}));render()}
function pointTime(p){return val(p,'confirmation_timestamp')!=='SIN_DATO'?val(p,'confirmation_timestamp'):val(p,'pivot_timestamp')}
function initTimeRange(){const a=document.getElementById('timeFrom'),b=document.getElementById('timeTo');const max=Math.max(0,TIMES.length-1);a.max=max;b.max=max;a.value=0;b.value=max;updateTimeLabel()}
function updateTimeLabel(){const a=+document.getElementById('timeFrom').value,b=+document.getElementById('timeTo').value;document.getElementById('timeLabel').textContent=TIMES.length?`${TIMES[Math.min(a,b)]} → ${TIMES[Math.max(a,b)]}`:'Sin timestamps'}
function filtered(){const field=document.getElementById('colorBy').value,s=document.getElementById('sourceFilter').value,side=document.getElementById('sideFilter').value,d=document.getElementById('datasetFilter').value,q=document.getElementById('pivotSearch').value.trim().toLowerCase();const lo=TIMES.length?TIMES[Math.min(+document.getElementById('timeFrom').value,+document.getElementById('timeTo').value)]:'';const hi=TIMES.length?TIMES[Math.max(+document.getElementById('timeFrom').value,+document.getElementById('timeTo').value)]:'';return POINTS.filter(p=>activeGroups.has(val(p,field))&&(s==='ALL'||val(p,'source_file')===s)&&(side==='ALL'||val(p,'pivot_side')===side)&&(d==='ALL'||val(p,'dataset_date')===d)&&(!q||val(p,'pivot_id').toLowerCase().includes(q))&&(!TIMES.length||(pointTime(p)>=lo&&pointTime(p)<=hi)))}
function nearestTo(p,rows,k){return rows.filter(r=>r!==p).map(r=>({p:r,d:(r.x-p.x)**2+(r.y-p.y)**2})).sort((a,b)=>a.d-b.d).slice(0,k).map(x=>x.p)}
function render(){if(typeof Plotly==='undefined'){document.getElementById('offline').style.display='block';return}const rows=filtered(),field=document.getElementById('colorBy').value;document.getElementById('visibleCount').textContent=rows.length;const counts={};rows.forEach(p=>counts[val(p,field)]=(counts[val(p,field)]||0)+1);const groups=Object.keys(counts).sort();document.getElementById('groupCount').textContent=groups.length;document.getElementById('dominantGroup').textContent=groups.length?groups.slice().sort((a,b)=>counts[b]-counts[a])[0]:'—';const size=+document.getElementById('sizeRange').value,opacity=+document.getElementById('opacityRange').value/100;const traces=[];
if(document.getElementById('densityToggle').checked){groups.forEach(g=>{const r=rows.filter(p=>val(p,field)===g);if(r.length>=8)traces.push({type:'histogram2dcontour',name:`Densidad ${g}`,x:r.map(p=>p.x),y:r.map(p=>p.y),colorscale:[[0,'rgba(0,0,0,0)'],[1,colorMap[g]]],showscale:false,ncontours:7,contours:{coloring:'fill',showlines:false},opacity:.20,hoverinfo:'skip',showlegend:false})})}
groups.forEach(g=>{const r=rows.filter(p=>val(p,field)===g);traces.push({type:'scattergl',mode:'markers',name:g,x:r.map(p=>p.x),y:r.map(p=>p.y),customdata:r,marker:{size,opacity,color:colorMap[g],line:{width:.35,color:'#e2e8f0'}},hovertemplate:`<b>${esc(g)}</b><br>Estado: %{customdata.target}<br>pivot_id: %{customdata.pivot_id}<br>Pivot: %{customdata.pivot_timestamp}<br>Archivo: %{customdata.source_file}<br>Lado: %{customdata.pivot_side}<br>Estructura: %{customdata.structure_type}<br>Liquidez: %{customdata.liquidity_type}<br>ATR(14): %{customdata.atr_14}<br>Volumen ratio: %{customdata.volume_ratio_20}<br>FVG: %{customdata.nearest_fvg_type}<br>Order Block: %{customdata.nearest_ob_type}<br>t-SNE 1: %{x:.4f}<br>t-SNE 2: %{y:.4f}<extra></extra>`})});
if(selectedPoint&&rows.includes(selectedPoint)){const k=+document.getElementById('kRange').value;selectedNeighbors=document.getElementById('neighborsToggle').checked?nearestTo(selectedPoint,rows,k):[];if(selectedNeighbors.length)traces.push({type:'scattergl',mode:'markers',name:`${selectedNeighbors.length} vecinos`,x:selectedNeighbors.map(p=>p.x),y:selectedNeighbors.map(p=>p.y),customdata:selectedNeighbors,marker:{size:size+5,color:'rgba(250,204,21,.18)',line:{width:2,color:'#facc15'}},hovertemplate:'Vecino de %{customdata.pivot_id}<extra></extra>'});traces.push({type:'scattergl',mode:'markers',name:'Punto seleccionado',x:[selectedPoint.x],y:[selectedPoint.y],customdata:[selectedPoint],marker:{size:size+10,symbol:'star',color:'#ffffff',line:{width:2,color:'#facc15'}},hovertemplate:'<b>Punto seleccionado</b><br>pivot_id: %{customdata.pivot_id}<extra></extra>'})}
const layout={autosize:true,paper_bgcolor:'#090f1d',plot_bgcolor:'#101827',font:{color:'#e5e7eb'},margin:{l:58,r:18,t:48,b:52},title:{text:`Proyección t-SNE — color por ${LABELS[field]||field}`,font:{size:18}},xaxis:{title:'t-SNE 1',gridcolor:'#273650',zerolinecolor:'#334155',automargin:true},yaxis:{title:'t-SNE 2',gridcolor:'#273650',zerolinecolor:'#334155',automargin:true},legend:{orientation:'h',y:1.08,x:0},hovermode:'closest',dragmode:'pan',uirevision:'keep'};Plotly.react('plot',traces,layout,{responsive:true,displaylogo:false,scrollZoom:true,modeBarButtonsToRemove:['lasso2d']}).then(()=>{document.getElementById('plot').on('plotly_click',e=>{const p=e.points[0].customdata;if(p&&p.x!==undefined){selectedPoint=p;showDetails(p);render()}})})}
function showDetails(p){selectedPoint=p;shell.classList.add('details-open');const preferred=['target','pivot_id','pivot_timestamp','confirmation_timestamp','source_file','dataset_date','pivot_side','structure_type','structure_mode','candle_direction','pivot_price','pivot_volume','atr_14','range_atr_ratio','volume_ratio_20','volume_zscore_20','liquidity_type','last_structure_event','last_structure_event_direction','near_equal_level','equal_level_type','inside_fvg','nearest_fvg_type','distance_fvg_atr','fvg_mitigated','inside_order_block','nearest_ob_type','distance_ob_atr','ob_invalidated','swing_size_atr','liquidity_imbalance_100'];document.getElementById('detailContent').innerHTML=preferred.filter(k=>p[k]!==undefined&&String(p[k])!=='').map(k=>`<div class="detail-row"><b>${esc(LABELS[k]||k)}</b><span>${esc(p[k])}</span></div>`).join('')||'<div class="empty">No hay datos adicionales.</div>';setTimeout(()=>Plotly.Plots.resize('plot'),210)}
function reset(){['sourceFilter','sideFilter','datasetFilter'].forEach(id=>document.getElementById(id).value='ALL');document.getElementById('pivotSearch').value='';document.getElementById('colorBy').value='target';document.getElementById('sizeRange').value=6;document.getElementById('opacityRange').value=60;document.getElementById('sizeValue').textContent='6';document.getElementById('opacityValue').textContent='0.60';document.getElementById('densityToggle').checked=false;document.getElementById('neighborsToggle').checked=true;document.getElementById('kRange').value=10;document.getElementById('kValue').textContent='10';selectedPoint=null;initTimeRange();rebuildGroups()}
function esc(s){return String(s).replace(/[&<>'"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[c]))}function escAttr(s){return esc(s)}
document.getElementById('colorBy').addEventListener('change',rebuildGroups);['sourceFilter','sideFilter','datasetFilter'].forEach(id=>document.getElementById(id).addEventListener('change',render));document.getElementById('pivotSearch').addEventListener('input',render);document.getElementById('sizeRange').addEventListener('input',e=>{document.getElementById('sizeValue').textContent=e.target.value;render()});document.getElementById('opacityRange').addEventListener('input',e=>{document.getElementById('opacityValue').textContent=(e.target.value/100).toFixed(2);render()});['timeFrom','timeTo'].forEach(id=>document.getElementById(id).addEventListener('input',()=>{updateTimeLabel();selectedPoint=null;render()}));document.getElementById('densityToggle').addEventListener('change',render);document.getElementById('neighborsToggle').addEventListener('change',render);document.getElementById('kRange').addEventListener('input',e=>{document.getElementById('kValue').textContent=e.target.value;render()});document.getElementById('fitBtn').addEventListener('click',()=>Plotly.relayout('plot',{'xaxis.autorange':true,'yaxis.autorange':true}));document.getElementById('resetBtn').addEventListener('click',reset);document.getElementById('downloadBtn').addEventListener('click',()=>Plotly.downloadImage('plot',{format:'png',filename:'tsne_interactive',width:1800,height:1100,scale:1}));document.getElementById('closeDetails').addEventListener('click',()=>{selectedPoint=null;selectedNeighbors=[];shell.classList.remove('details-open');setTimeout(()=>Plotly.Plots.resize('plot'),210)});document.getElementById('toggleSidebar').addEventListener('click',()=>{shell.classList.add('sidebar-closed');document.getElementById('openSidebar').style.display='block';setTimeout(()=>Plotly.Plots.resize('plot'),210)});document.getElementById('openSidebar').addEventListener('click',()=>{shell.classList.remove('sidebar-closed');document.getElementById('openSidebar').style.display='none';setTimeout(()=>Plotly.Plots.resize('plot'),210)});window.addEventListener('resize',()=>Plotly.Plots.resize('plot'));rebuildGroups();
</script></body></html>
JS
close $fh or die "No se pudo cerrar '$output': $!\n";

print "\n========================================\n";
print " VISUALIZACIÓN t-SNE INTERACTIVA V3\n";
print "========================================\n";
print "Puntos incluidos: " . scalar(@points) . "\n";
print "Variables disponibles: " . scalar(@$columns) . "\n";
print "ADVERTENCIA: la proyección parece antigua; ejecute perl tsne_pipeline.pl para exportar todas las variables.\n" if scalar(@$columns) < 50;
print "HTML generado: $output\n";
print "========================================\n";

if (!$no_open) {
    my $opened = open_browser($output);
    print $opened ? "Navegador abierto automáticamente.\n" : "Abra manualmente: $output\n";
}

sub unique_nonempty {
    my ($points, $field) = @_;
    my %seen;
    for my $p (@$points) {
        my $v = value_or($p->{$field}, '');
        $seen{$v} = 1 if $v ne '';
    }
    return [sort keys %seen];
}

sub open_browser {
    my ($file) = @_;
    my $absolute = File::Spec->rel2abs($file);
    my @commands;
    if ($^O eq 'MSWin32') { push @commands, ['cmd','/c','start','',$absolute]; }
    elsif ($^O eq 'darwin') { push @commands, ['open',$absolute]; }
    else {
        push @commands, ['wslview',$absolute] if command_exists('wslview');
        push @commands, ['xdg-open',$absolute] if command_exists('xdg-open');
        push @commands, ['gio','open',$absolute] if command_exists('gio');
    }
    for my $cmd (@commands) {
        my $pid=fork(); next if !defined $pid;
        if ($pid==0) { open STDOUT,'>',File::Spec->devnull(); open STDERR,'>',File::Spec->devnull(); exec @$cmd; exit 1; }
        waitpid($pid,0); return 1 if $?==0;
    }
    return 0;
}
sub command_exists { my ($name)=@_; for my $dir (File::Spec->path()) { return 1 if -x File::Spec->catfile($dir,$name) } return 0; }
sub value_or { my ($v,$f)=@_; return defined($v)&&$v ne ''?$v:$f; }
sub json_encode { my ($v)=@_; return 'null' if !defined $v; return '['.join(',',map{json_encode($_)}@$v).']' if ref($v) eq 'ARRAY'; return '{'.join(',',map{json_string($_).':'.json_encode($v->{$_})}sort keys%$v).'}' if ref($v) eq 'HASH'; return $v if !ref($v)&&$v=~/^-?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$/; return json_string($v); }
sub json_string { my ($t)=@_; $t='' if !defined$t; $t=~s/\\/\\\\/g;$t=~s/"/\\"/g;$t=~s/\r/\\r/g;$t=~s/\n/\\n/g;$t=~s/\t/\\t/g;$t=~s/([\x00-\x1f])/sprintf('\\u%04x',ord($1))/ge;return qq{"$t"}; }
sub read_csv_hashes {
    my ($file)=@_; open my $in,'<:encoding(UTF-8)',$file or die "No se puede leer '$file': $!\n";
    my $header=<$in>; die "CSV sin cabecera\n" if !defined$header; chomp$header;$header=~s/\r$//;my @h=parse_csv_line($header);my @r;
    while(my $line=<$in>){chomp$line;$line=~s/\r$//;next if $line eq '';my @v=parse_csv_line($line);my %row;@row{@h}=@v;push @r,\%row}close$in;return (\@r,\@h);
}
sub parse_csv_line { my ($line)=@_;my(@v,$c);my$in_q=0;for(my$i=0;$i<length$line;$i++){my$ch=substr($line,$i,1);if($in_q){if($ch eq '"'){if($i+1<length$line&&substr($line,$i+1,1) eq '"'){$c.='"';$i++}else{$in_q=0}}else{$c.=$ch}}else{if($ch eq '"'){$in_q=1}elsif($ch eq ','){push@v,$c;$c=''}else{$c.=$ch}}}push@v,$c;return@v;}
