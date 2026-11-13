var Q=[],qid=0,qpaused=false,curJob=null,HIST=[],batchN=0,cdT=null;
function qe(x){return String(x==null?'':x).replace(/[&<>"]/g,function(c){return{'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]})}
function enqueue(o,label,kind){var d=new Date(),z=function(n){return String(n).padStart(2,'0')};o.stamp=d.getFullYear()+'-'+z(d.getMonth()+1)+'-'+z(d.getDate())+' '+z(d.getHours())+'-'+z(d.getMinutes());Q.push({id:++qid,o:o,label:label,kind:kind,state:'queued',miss:0});qpaused=false;renderQ();pump();var n=$('ck');if(n){n.textContent=t('q_added');setTimeout(function(){if(n.textContent===t('q_added'))n.textContent=''},2500)}}
async function pump(){if(curJob||qpaused||!ready||running)return;var j=Q.find(function(x){return x.state==='queued'});if(!j)return;
 curJob=j;j.state='starting';renderQ();var r;try{r=await api('start',j.o)}catch(e){r={error:String(e)}}
 if(r&&r.error){j.state='failed';j.err=r.error;curJob=null;renderQ();setTimeout(pump,300);return}
 j.state='running';j.seen=false;j.miss=0;renderQ()}
function qTick(s){if(curJob&&curJob.state==='running'){if(s.running)curJob.seen=true;
  if(!s.running&&(curJob.seen||++curJob.miss>4))finishJob(s);else renderQ(true)}
 else if(!curJob)pump()}
function finishJob(s){var j=curJob;curJob=null;var nf=s.nfiles||0,fl=(s.fails||[]).length;
 j.n=nf;j.fails=fl;j.files=s.files||[];j.state=j.stopped?'stopped':(nf===0&&fl>0?'failed':'done');batchN+=nf;
 api('history',{entry:{t:Date.now(),label:j.label,kind:j.kind,ok:j.state==='done',n:nf,fails:fl,files:j.files.slice(0,40)}}).then(loadHist);
 renderQ();
 if(!qpaused&&!Q.some(function(x){return x.state==='queued'})){if(!j.stopped)allDone();batchN=0}else setTimeout(pump,300)}
function allDone(){if($('notif').checked)api('notify',{title:'KoeDL',text:t('ntf_done').replace('{n}',batchN)});
 var a=$('after').value;if(a==='quit'||a==='off')cdStart(a)}
function cdStart(a){var n=30;cdCancel();$('cd').hidden=false;var tick=function(){$('cdt').textContent=t(a==='off'?'cd_o':'cd_q').replace('{n}',n)};tick();
 cdT=setInterval(function(){n--;if(n<=0){clearInterval(cdT);cdT=null;$('cd').hidden=true;if(a==='off')api('poweroff',{});else api('quit',{})}else tick()},1000)}
function cdCancel(){if(cdT){clearInterval(cdT);cdT=null}$('cd').hidden=true}
function qPause(){qpaused=!qpaused;renderQ();if(!qpaused)pump()}
function qClear(){Q=Q.filter(function(x){return x.state==='queued'||x.state==='running'||x.state==='starting'});renderQ()}
function stopQ(){if(curJob)curJob.stopped=true;qpaused=true;api('stop',{});renderQ()}
async function loadHist(){try{var r=await api('history');HIST=Array.isArray(r)?r:[];}catch(e){HIST=[]}renderH()}
async function hClear(){await api('history',{clear:true});loadHist()}
var qsT=null;var qOk=false;function qSave(){if(!qOk)return;clearTimeout(qsT);qsT=setTimeout(function(){var a=Q.filter(function(x){return x.state!=='done'}).map(function(x){return{id:x.id,label:x.label,kind:x.kind,state:(x.state==='failed'||x.state==='stopped')?x.state:'queued',o:x.o}});try{api('queue',RS.concat(a))}catch(e){}},300)}
async function qLoad(){try{var a=await api('queue');if(!Array.isArray(a)||!a.length){qOk=true;return}qOk=true;RS=a;$('rst').textContent=t('rs_msg').replace('{n}',a.filter(function(x){return x.state==='queued'}).length||a.length);$('rs').hidden=false}catch(e){qOk=true}}
var RS=[];function rsGo(){$('rs').hidden=true;RS.forEach(function(x){x.o.reset=false;x.miss=0;if(x.state==='queued'||x.state==='stopped'||x.state==='failed')x.state='queued';x.id=++qid;Q.push(x)});RS=[];qpaused=false;renderQ();pump()}
function rsDrop(){$('rs').hidden=true;RS=[];qSave()}
function renderQ(light){var L=$('qlist');if(!L)return;if(!light)qSave();var n=Q.filter(function(x){return x.state==='queued'||x.state==='running'||x.state==='starting'}).length;$('qn').textContent=n||'';
 $('qpause').textContent=t(qpaused?'q_resume':'q_pause');$('qpause').classList.toggle('hide',!Q.length);
 if(!Q.length){L.innerHTML='<div class="emp">'+qe(t('q_empty'))+'</div>';return}
 var hh=Q.slice().reverse().map(function(j){var st=j.state==='starting'?'running':j.state,meta='';
  if(st==='running'){var s=lastStatus||{};meta=(s.pct?Math.round(s.pct)+'%':'')+(s.speed?' · '+s.speed:'')+(s.cur?' · '+s.cur:'')}
  else if(st==='done')meta=j.n?j.n+t('q_files'):t('q_nonew');else if(st==='failed')meta=j.err||((j.fails||0)+' ✕');else if(st==='stopped')meta=qpaused?t('q_paused_note'):'';
  var b='';if(st==='queued'||st==='done'||st==='failed'||st==='stopped')b+='<button class="s" data-qa="rm" data-id="'+j.id+'" title="'+qe(t('q_remove'))+'">✕</button>';
  if(st==='failed'||st==='stopped')b='<button class="s" data-qa="retry" data-id="'+j.id+'" title="'+qe(t('q_retry'))+'">↻</button>'+b;
  if(st==='done'&&j.files&&j.files.length)b='<button class="s" data-qa="play" data-id="'+j.id+'" title="'+qe(t('q_play'))+'">▶</button><button class="s" data-qa="open" data-id="'+j.id+'" title="'+qe(t('q_open'))+'">📂</button>'+b;
  return '<div class="qi st-'+st+'"><span class="qs">'+qe(t('q_st_'+st))+'</span><div class="qt"><b title="'+qe(j.label)+'">'+qe(j.label)+'</b><small>'+qe(meta)+'</small></div><div class="qa">'+b+'</div></div>'}).join('');if(L.dataset.h!==hh){L.innerHTML=hh;L.dataset.h=hh}}
function renderH(){var L=$('hlist');if(!L)return;if(!HIST.length){L.innerHTML='<div class="emp">'+qe(t('h_empty'))+'</div>';return}
 L.innerHTML=HIST.map(function(h,i){var d=new Date(h.t),ds=isNaN(d)?'':d.toLocaleString([],{day:'2-digit',month:'2-digit',hour:'2-digit',minute:'2-digit'});
  var meta=ds+' · '+(h.n?h.n+t('q_files'):t('q_nonew'))+(h.fails?' · '+h.fails+' ✕':'');
  return '<div class="qi st-'+(h.ok?'done':'failed')+'"><span class="qs">'+(h.kind==='v'?'🎬':'🎵')+'</span><div class="qt"><b title="'+qe(h.label)+'">'+qe(h.label)+'</b><small>'+qe(meta)+'</small></div><div class="qa">'+((h.files&&h.files.length)?'<button class="s" data-ha="play" data-i="'+i+'" title="'+qe(t('q_play'))+'">▶</button><button class="s" data-ha="open" data-i="'+i+'" title="'+qe(t('q_open'))+'">📂</button>':'')+'</div></div>'}).join('')}
document.addEventListener('click',function(e){var b=e.target.closest&&e.target.closest('button[data-qa],button[data-ha]');if(!b)return;
 if(b.dataset.qa){var j=Q.find(function(x){return x.id==b.dataset.id});if(!j)return;
  if(b.dataset.qa==='rm'){Q=Q.filter(function(x){return x!==j});renderQ()}
  else if(b.dataset.qa==='retry'){j.state='queued';j.stopped=false;j.err='';qpaused=false;renderQ();pump()}
  else if(b.dataset.qa==='play'&&j.files&&j.files[0])libPlayFile(j.files[0],'',j.kind)
  else if(b.dataset.qa==='open'&&j.files&&j.files[0])api('openfile',{path:j.files[0]})}
 else if(b.dataset.ha==='play'||b.dataset.ha==='open'){var h=HIST[+b.dataset.i];if(h&&h.files&&h.files[0]){if(b.dataset.ha==='play')libPlayFile(h.files[0],'',h.kind);else api('openfile',{path:h.files[0]})}}});
/* arrastar e soltar links */
addEventListener('dragover',function(e){e.preventDefault()});
addEventListener('drop',function(e){e.preventDefault();var dt=e.dataTransfer;if(!dt)return;var tx=(dt.getData('text/uri-list')||dt.getData('text/plain')||'').split(/\r?\n/).map(function(x){return x.trim()}).filter(function(x){return /^https?:\/\//.test(x)});
 if(!tx.length)return;var ta=$('urls');ta.value=(ta.value.trim()?ta.value.trim()+'\n':'')+tx.join('\n');tab('links')});
/* colar sozinho o link copiado */
