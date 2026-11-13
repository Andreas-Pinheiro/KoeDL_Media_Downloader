/* ---- Biblioteca / player ---- */
var LIB=[],LF='all',LCUR='',LSHOW=[],LM=null,LREP=0,LSHUF=false,LSORT='new',LSEEK=false,LDIRS={dirs:[],base:[]};
function lprefLoad(){try{var o=JSON.parse(localStorage.getItem('koedl_lib')||'{}');if(o.rep!==undefined)LREP=+o.rep||0;LSHUF=!!o.shuf;if(o.sort)LSORT=o.sort;if(o.f)LF=o.f;if(o.vol!==undefined)$('lvol').value=o.vol;if(o.spd)$('lspd').value=o.spd}catch(e){}}
function lprefSave(){try{localStorage.setItem('koedl_lib',JSON.stringify({rep:LREP,shuf:LSHUF,sort:LSORT,f:LF,vol:+$('lvol').value,spd:$('lspd').value}))}catch(e){}}
function lfmt(s){if(!isFinite(s)||s<0)s=0;s=Math.floor(s);var h=Math.floor(s/3600),m=Math.floor(s%3600/60),r=s%60;return(h?h+':'+(m<10?'0':''):'')+m+':'+(r<10?'0':'')+r}
function lsize(n){return n>=1073741824?(n/1073741824).toFixed(1)+' GB':n>=1048576?Math.round(n/1048576)+' MB':Math.max(1,Math.round(n/1024))+' KB'}
function lshown(){var q=$('lq').value.trim().toLowerCase(),a=LIB.filter(function(x){return(LF==='all'||x.k===LF)&&(!q||(x.n+' '+x.d).toLowerCase().indexOf(q)>=0)});
 if(LSORT==='az')a.sort(function(x,y){return x.n.localeCompare(y.n)});else if(LSORT==='big')a.sort(function(x,y){return y.s-x.s});return a}
function libTitles(){var m={lshuf:'lib_shuf',lprev:'lib_prev',lplay:'lib_play',lnext:'lib_next',lrep:'lib_rep',lmute:'lib_mute',lfs:'lib_fs',lopen:'lib_open',lext:'lib_ext',lref:'lib_refresh',lseek:'lib_seek',lvol:'lib_vol',lspd:'lib_spd'};for(var k in m)$(k).title=t(m[k])}
function lui(){$('lshuf').classList.toggle('on',LSHUF);$('lrep').classList.toggle('on',LREP>0);$('lrep').textContent=LREP===2?'↻¹':'↻';$('lrep').title=t('lib_rep')+': '+t(['lib_rep0','lib_rep1','lib_rep2'][LREP]);
 $('lplay').textContent=(LM&&LM.src&&!LM.paused)?'⏸':'▶';$('lstage').classList.toggle('playing',!!(LM&&LM.src&&!LM.paused));
 $('lmute').textContent=($('pa').muted||$('pv').muted||+$('lvol').value===0)?'🔇':'🔊';
 [$('lseek'),$('lvol')].forEach(function(r){r.style.setProperty('--p',(r.value-r.min)/(r.max-r.min)*100+'%')})}
async function libLoad(){try{var r=await api('library');LIB=Array.isArray(r)?r:[];libRender()}catch(e){LIB=[];libRender()}libDirsLoad()}
function libRender(){var a=lshown();LSHOW=a;$('lcount').textContent=t('lib_count').replace('{n}',a.length);
 $('lseg').querySelectorAll('button').forEach(function(b){b.classList.toggle('on',b.dataset.f===LF)});$('lsort').value=LSORT;
 $('llist').innerHTML=a.length?a.map(function(x,i){return'<div class="li'+(x.p===LCUR?' on':'')+'" data-i="'+i+'"><span class="ic">'+(x.k==='v'?'🎬':'♪')+'</span><span class="lt"><b>'+esc(x.n)+'</b><small>'+esc((x.d?x.d+' · ':'')+lsize(x.s))+'</small></span><button class="lo" type="button" data-o="'+i+'" title="'+esc(t('lib_open'))+'">📂</button></div>'}).join(''):'<div class="emp">'+esc(t('lib_empty'))+'</div>';libTitles();lui()}
function libCur(){for(var i=0;i<LIB.length;i++)if(LIB[i].p===LCUR)return LIB[i];return null}
function libPlay(x){if(!x)return;var v=x.k==='v',m=v?$('pv'):$('pa'),o=v?$('pa'):$('pv');try{o.pause();o.removeAttribute('src');o.load()}catch(e){}
 LM=m;LCUR=x.p;$('lerr').textContent='';$('lstage').classList.toggle('vid',v);$('lnow').textContent=x.n;$('lsub').textContent=(x.d?x.d+' · ':'')+(v?t('lib_v'):t('lib_a'))+' · '+lsize(x.s);
 m.volume=+$('lvol').value/100;m.playbackRate=+$('lspd').value;m.src='/api/media?t='+encodeURIComponent(T)+'&p='+encodeURIComponent(x.p);var pr=m.play();if(pr&&pr.catch)pr.catch(function(){});
 try{if('mediaSession' in navigator){navigator.mediaSession.metadata=new MediaMetadata({title:x.n,artist:x.d||'KoeDL'});navigator.mediaSession.setActionHandler('previoustrack',function(){libStep(-1)});navigator.mediaSession.setActionHandler('nexttrack',function(){libStep(1)})}}catch(e){}
 libRender();var el=$('llist').querySelector('.li.on');if(el&&el.scrollIntoView)try{el.scrollIntoView({block:'nearest'})}catch(e){}}
function libToggle(){if(!LM||!LM.src){var a=LSHOW.length?LSHOW:lshown();if(a.length)libPlay(LSHUF?a[Math.floor(Math.random()*a.length)]:a[0]);return}if(LM.paused){var p=LM.play();if(p&&p.catch)p.catch(function(){})}else LM.pause()}
function libStep(d,auto){var a=LSHOW;if(!a.length)return;var i=-1;for(var k=0;k<a.length;k++)if(a[k].p===LCUR){i=k;break}
 if(auto&&LREP===2&&i>=0){LM.currentTime=0;LM.play();return}
 var n;if(LSHUF&&a.length>1){do{n=Math.floor(Math.random()*a.length)}while(n===i)}else{n=i+d;if(n>=a.length){if(auto&&LREP===0){lui();return}n=0}if(n<0)n=a.length-1}libPlay(a[n])}
async function libFile(mode){var x=libCur();if(!x){$('lerr').textContent=t('lib_pick');return}$('lerr').textContent='';try{var r=await api('openfile',{path:x.p,mode:mode});if(r&&r.error)$('lerr').textContent=r.error}catch(e){$('lerr').textContent=t('lib_fail')}}
function libMedia(m){m.addEventListener('timeupdate',function(){if(LM!==m)return;if(!LSEEK&&m.duration){$('lseek').value=Math.round(m.currentTime/m.duration*1000)}$('ltc').textContent=lfmt(m.currentTime);lui()});
 m.addEventListener('loadedmetadata',function(){if(LM===m)$('ltd').textContent=lfmt(m.duration)});m.addEventListener('play',lui);m.addEventListener('pause',lui);m.addEventListener('volumechange',lui);
 m.addEventListener('ended',function(){if(LM===m)libStep(1,true)});
 m.addEventListener('error',function(){if(LM===m&&m.getAttribute('src')){$('lerr').textContent=t('lib_err');lui()}})}
libMedia($('pa'));libMedia($('pv'));
$('lplay').onclick=libToggle;$('lprev').onclick=function(){if(LM&&LM.currentTime>3){LM.currentTime=0}else libStep(-1)};$('lnext').onclick=function(){libStep(1)};
$('lshuf').onclick=function(){LSHUF=!LSHUF;lprefSave();lui()};$('lrep').onclick=function(){LREP=(LREP+1)%3;lprefSave();lui()};
$('lseek').addEventListener('input',function(){LSEEK=true;if(LM&&LM.duration){$('ltc').textContent=lfmt(this.value/1000*LM.duration)}lui()});
$('lseek').addEventListener('change',function(){if(LM&&LM.duration)LM.currentTime=this.value/1000*LM.duration;LSEEK=false});
$('lvol').addEventListener('input',function(){var v=+this.value/100;$('pa').volume=v;$('pv').volume=v;$('pa').muted=$('pv').muted=false;lprefSave();lui()});
$('lmute').onclick=function(){var m=!($('pa').muted||$('pv').muted);$('pa').muted=$('pv').muted=m;lui()};
$('lspd').onchange=function(){$('pa').playbackRate=$('pv').playbackRate=+this.value;lprefSave()};
$('lfs').onclick=function(){var s=$('lscreen');try{if(document.fullscreenElement)document.exitFullscreen();else if(s.requestFullscreen)s.requestFullscreen()}catch(e){}};
$('pv').addEventListener('click',libToggle);$('pv').addEventListener('dblclick',function(){$('lfs').click()});
$('lopen').onclick=function(){libFile('select')};$('lext').onclick=function(){libFile('open')};$('lref').onclick=libLoad;
$('llist').addEventListener('click',function(e){var o=e.target.closest('[data-o]');if(o){var x=LSHOW[+o.dataset.o];if(x){LCUR=x.p;libRender();libFile('select')}return}var r=e.target.closest('.li');if(r)libPlay(LSHOW[+r.dataset.i])});
$('lseg').addEventListener('click',function(e){var b=e.target.closest('button[data-f]');if(b){LF=b.dataset.f;lprefSave();libRender()}});
$('lq').addEventListener('input',libRender);$('lsort').addEventListener('change',function(){LSORT=this.value;lprefSave();libRender()});
document.addEventListener('keydown',function(e){if(document.body.dataset.tab!=='lib')return;var g=e.target&&e.target.tagName;if(g==='INPUT'||g==='SELECT'||g==='TEXTAREA'||e.ctrlKey||e.altKey||e.metaKey)return;
 if(e.code==='Space'){e.preventDefault();libToggle()}else if(e.key==='ArrowRight'&&LM&&LM.duration){LM.currentTime=Math.min(LM.duration,LM.currentTime+5)}else if(e.key==='ArrowLeft'&&LM){LM.currentTime=Math.max(0,LM.currentTime-5)}else if(e.key==='n'||e.key==='N')libStep(1);else if(e.key==='p'||e.key==='P')libStep(-1)});
/* pastas extras da biblioteca (musicas que nao foram baixadas pelo app) */
async function libDirsLoad(){try{LDIRS=await api('libdirs');if(!LDIRS||!LDIRS.dirs)LDIRS={dirs:[],base:[]}}catch(e){}libDirsRender()}
function libDirsRender(){var h=(LDIRS.base||[]).map(function(d){return'<div class="lfr"><span>'+esc(d)+'</span><em>'+esc(t('lib_f_dl'))+'</em></div>'}).join('')+(LDIRS.dirs||[]).map(function(d,i){return'<div class="lfr"><span>'+esc(d.p)+(d.ok?'':' <em>'+esc(t('lib_f_miss'))+'</em>')+'</span><button class="s" type="button" data-rm="'+i+'">'+esc(t('lib_rm'))+'</button></div>'}).join('');$('lfl').innerHTML=h}
async function libDirsSave(list){$('lfmsg').textContent='';try{var r=await api('libdirs',{dirs:list});if(r&&r.error){$('lfmsg').textContent=r.error;return false}if(r&&r.bad&&r.bad.length)$('lfmsg').textContent=t('lib_f_bad')+r.bad.join(', ');await libLoad();return true}catch(e){$('lfmsg').textContent=t('lib_fail');return false}}
function libDirsCur(){return(LDIRS.dirs||[]).map(function(d){return d.p})}
$('lfl').addEventListener('click',function(e){var b=e.target.closest('[data-rm]');if(b){var l=libDirsCur();l.splice(+b.dataset.rm,1);libDirsSave(l)}});
$('lpadd').onclick=async function(){var v=$('lpath').value.trim();if(!v)return;var l=libDirsCur();l.push(v);if(await libDirsSave(l))$('lpath').value=''};
$('lpath').addEventListener('keydown',function(e){if(e.key==='Enter')$('lpadd').click()});
$('ladd').onclick=async function(){$('lfmsg').textContent=t('lib_f_pick');try{var r=await api('pickfolder',{});if(r&&r.busy===false&&!r.path&&!r.busy){$('lfmsg').textContent=t('lib_f_nopick');return}
 var tries=0;while(tries++<600){await new Promise(function(z){setTimeout(z,1000)});r=await api('pickfolder');if(!r.busy)break}
 if(r&&r.path){var l=libDirsCur();l.push(r.path);await libDirsSave(l)}else $('lfmsg').textContent=''}catch(e){$('lfmsg').textContent=t('lib_fail')}};
lprefLoad();var _al2=applyLang;applyLang=function(){_al2.apply(this,arguments);libRender();libDirsRender()};
