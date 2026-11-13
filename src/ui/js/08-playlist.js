function vis(){const q=$('plfilter').value.trim().toLowerCase();return P.items.map((x,i)=>[x,i]).filter(p=>!q||(p[0].title+' '+p[0].uploader).toLowerCase().indexOf(q)>=0)}
function render(){const v=vis();$('tb').innerHTML=v.map(p=>{const x=p[0],i=p[1];return`<tr class="${x.unavail?'na':''}"><td><input type="checkbox" data-i="${i}" ${x.checked?'checked':''} ${x.unavail?'disabled':''}></td><td class="num">${esc(x.idx)}</td><td>${esc(x.title)}</td><td>${esc(x.uploader)}</td><td>${esc(x.dur)}</td><td>${x.unavail?t('unavail'):`<select data-t2="${i}"><option value="a" ${x.type==='a'?'selected':''}>${t('opt_a')}</option><option value="v" ${x.type==='v'?'selected':''}>${t('opt_v')}</option></select>`}</td></tr>`}).join('');sum()}
function sum(){updGop();const s=P.items.filter(x=>x.checked&&!x.unavail),a=s.filter(x=>x.type==='a').length;
if(P.items.length)$('plinfo').textContent=(P.busy?t('pl_loading'):'')+(P.title?'“'+P.title+'” · ':'')+P.items.length+t('pl_tracks')+s.length+t('pl_marked')+a+t('pl_audio')+(s.length-a)+t('pl_video')}
function mark(m){for(const p of vis()){const x=p[0];if(x.unavail)continue;x.checked=m===2?!x.checked:!!m}render()}
/* Desistiu da playlist/musica: esvazia o link, a lista carregada e a selecao (nao mexe na fila de downloads). */
function clearAll(){
 if(P.busy){try{api('pl/stop',{})}catch(e){}}
 P={items:[],from:0,busy:false,title:'',url:''};
 ['urls','plurl','plfilter'].forEach(function(id){var e=$(id);if(e)e.value=''});
 $('tb').innerHTML='';$('ck').textContent='';$('plinfo').textContent=t('plhint');
 updGop();var u=$('urls');if(u)u.focus()}
$('tb').addEventListener('change',e=>{const g=e.target;if(g.dataset.i!==undefined){P.items[+g.dataset.i].checked=g.checked;sum()}
else if(g.dataset.t2!==undefined){P.items[+g.dataset.t2].type=g.value;setRadio('pm','m');updFmt();save();sum()}});
document.querySelectorAll('input[name=pm]').forEach(e=>e.addEventListener('change',()=>{const m=radio('pm');if(m!=='m'){P.items.forEach(x=>x.type=m);render()}updFmt()}));
/* ---- status ---- */
function showStatus(s){$('bar2').value=s.pct;
const nb=s.prep||s.note||((s.ver&&s.ver.ytdlp&&!s.ver.ffmpeg)?t('noff'):'');$('banner').style.display=nb?'block':'none';$('banner').textContent=nb;
chkDone(s);const uv=s.updavail||'';if(UPDGO){}else if(uv&&!UPDX[uv]){$('updb').classList.remove('hide');$('updt').textContent=t('upd_msg').replace('{v}',uv).replace('{c}',s.appver||'')}else $('updb').classList.add('hide');
$('appver').textContent=s.appver?('v'+s.appver):'';$('appver').title=t('appver_t');
$('ver').textContent=s.ver&&s.ver.ytdlp?('· yt-dlp '+s.ver.ytdlp+' · ffmpeg '+(s.ver.ffmpeg?String(s.ver.ffmpeg).slice(0,14):t('miss'))+' · deno '+(s.ver.deno?s.ver.deno:t('miss'))):'';
const idle=(s.status==='Idle'||s.status==='Parado');
let line=idle?t('idle'):s.status;
if(s.running&&s.total>0)line+=' · '+(s.done+1>s.total?s.total:s.done+1)+'/'+s.total;
if(s.running&&s.item)line+=' ('+t('item')+s.item+')';
if(s.running&&s.speed)line+=' · '+s.speed+(s.eta?' · ETA '+s.eta:'');
if(s.running&&s.browser&&s.browser!==t('nocookie')&&s.browser!=='sem cookies'&&s.browser!=='no cookies')line+=' · '+t('cookies')+s.browser;
$('stline').textContent=line;$('cur').textContent=s.cur||'';$('cur2').textContent=s.cur||'';
$('log').textContent=s.log.join('\n');if($('dt').open)$('log').scrollTop=1e9;
$('fails').textContent=s.fails.length?t('fails')+s.fails.join('\n'):'';$('alts').textContent=s.alts.length?t('alts')+s.alts.join('\n'):'';
$('dt').classList.toggle('has',!!(s.fails.length||s.alts.length));if(s.fails.length||s.alts.length)$('dt').open=true;
$('go').disabled=!s.ready;$('gop').disabled=!s.ready;$('stopb').disabled=!s.running}
async function poll(){try{const s=await api('status');running=s.running;ready=s.ready;lastStatus=s;showStatus(s);qTick(s)}catch(e){$('stline').textContent=t('closed')}}
$('tb').addEventListener('change',()=>{});
load();setInterval(poll,1000);poll();

(function(){ if(window.chrome&&window.chrome.webview) return; var tm; function sv(){ clearTimeout(tm); tm=setTimeout(function(){ try{ api('winsize',{x:window.screenX,y:window.screenY,w:window.outerWidth,h:window.outerHeight}) }catch(e){} },700) } window.addEventListener('resize',sv); })();

