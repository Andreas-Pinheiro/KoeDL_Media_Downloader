/* ---- Biblioteca / player ---- */
var LIB=[],LF='all',LCUR=-1,LSHOWN=[],LPLAYP='';
function fmtSz(n){return n>1048576?(n/1048576).toFixed(1)+' MB':Math.max(1,Math.round(n/1024))+' KB'}
function fmtDt(s){try{var d=new Date(s);return d.toLocaleDateString(LANG==='pt'?'pt-BR':'en-US')}catch(e){return ''}}
async function libLoad(){try{var r=await api('library');LIB=Array.isArray(r)?r:[]}catch(e){LIB=[]}libRender()}
function libRender(){var q=($('lq').value||'').toLowerCase().trim();LSHOWN=LIB.filter(function(x){return(LF==='all'||x.k===LF)&&(!q||(x.n+' '+(x.d||'')).toLowerCase().indexOf(q)>=0)});
 $('lcount').textContent=t('lib_count').replace('{n}',LSHOWN.length);
 var h=LSHOWN.map(function(x,i){return '<div class="li'+(x.p===LPLAYP?' on':'')+'" data-i="'+i+'"><span class="ic">'+(x.k==='a'?'♫':'▶')+'</span><div class="qt"><b>'+esc(x.n)+'</b><small>'+esc((x.d?x.d+' · ':'')+fmtSz(x.s)+' · '+fmtDt(x.t))+'</small></div></div>'}).join('');
 var L=$('llist');var nh=h||'<div class="emp">'+esc(t('lib_empty'))+'</div>';if(L.dataset.h!==nh){L.dataset.h=nh;L.innerHTML=nh}}
function libStart(x){if(!x||!x.p)return;LPLAYP=x.p;var u='/api/media?t='+encodeURIComponent(T)+'&p='+encodeURIComponent(x.p);
 var isV=x.k==='v',m=isV?$('pv'):$('pa'),o=isV?$('pa'):$('pv');try{o.pause();o.removeAttribute('src');o.load()}catch(e){}
 $('lplayer').className=isV?'v':'a';$('lnow').textContent=x.n||'';$('lerr').textContent='';m.src=u;var pr=m.play();if(pr&&pr.catch)pr.catch(function(){});libRender()}
function libPlay(i){var x=LSHOWN[i];if(!x)return;LCUR=LIB.indexOf(x);libStart(x)}
/* toca um arquivo qualquer dentro do player embutido (fila, historico, lista de baixados) sem abrir player externo */
function libPlayFile(p,n,k){if(!p)return;tab('lib');
 var x=null;for(var i=0;i<LIB.length;i++){if(LIB[i].p===p){LCUR=i;x=LIB[i];break}}
 if(!x){var nm=String(n||'').trim()||String(p).split(/[\\/]/).pop();var ext=(nm.indexOf('.')>=0?nm.split('.').pop():'').toLowerCase();
  LCUR=-1;x={p:p,n:nm.replace(/\.[^.]+$/,''),k:(k==='v'||k==='a'?k:(['mp4','mkv','webm','mov'].indexOf(ext)>=0?'v':'a')),s:0,t:''}}
 libStart(x);if(!LIB.length)libLoad()}
function libStep(d){if(!LSHOWN.length)return;var i=LSHOWN.findIndex(function(x){return x.p===LPLAYP});
 if(i<0){libPlay(d>0?0:LSHOWN.length-1);return}
 if($('lshuf').checked&&LSHOWN.length>1){var j;do{j=Math.floor(Math.random()*LSHOWN.length)}while(j===i);libPlay(j)}else libPlay((i+d+LSHOWN.length)%LSHOWN.length)}
['pv','pa'].forEach(function(id){var m=$(id);m.addEventListener('ended',function(){if($('lauto').checked)libStep(1)});m.addEventListener('error',function(){if(m.getAttribute('src'))$('lerr').textContent=t('lib_err')})});
$('llist').addEventListener('click',function(e){var r=e.target.closest&&e.target.closest('.li');if(r)libPlay(+r.dataset.i)});
$('lprev').onclick=function(){libStep(-1)};$('lnext').onclick=function(){libStep(1)};$('lref').onclick=libLoad;$('lq').addEventListener('input',libRender);
$('lopen').onclick=function(){var x=LIB[LCUR];if(x)api('openfile',{path:x.p})};
$('lseg').addEventListener('click',function(e){var b=e.target.closest&&e.target.closest('button[data-f]');if(!b)return;LF=b.dataset.f;[].forEach.call($('lseg').children,function(c){c.classList.toggle('on',c===b)});libRender()});
var _al2=applyLang;applyLang=function(){_al2.apply(this,arguments);libRender()};
