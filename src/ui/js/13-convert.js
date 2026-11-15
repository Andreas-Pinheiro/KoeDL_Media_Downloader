/* Aba "Converter": extrai o audio de videos com o ffmpeg que o KoeDL ja instala.
   A lista de arquivos so e montada pelo seletor nativo do programa (rota /api/conv/pick),
   entao a pagina nunca envia caminho nenhum: nao existe como pedir a conversao de outro arquivo. */
(function(){
 var FMT=[['mp3','MP3'],['m4a','M4A (AAC)'],['opus','Opus'],['flac','FLAC'],['wav','WAV']];
 var QS=[['320','320 kbps'],['256','256 kbps'],['192','192 kbps'],['128','128 kbps']];
 var timer=null,last=null;
 function flex(e,gap){e.style.cssText='display:flex;gap:'+(gap||8)+'px;flex-wrap:wrap;align-items:center';return e}
 function mk(tag,cls,txt){var e=document.createElement(tag);if(cls)e.className=cls;if(txt!=null)e.textContent=txt;return e}
 function t2(k){return (typeof t==='function')?t(k):k}
 function dur(s){s=Math.round(+s||0);if(s<=0)return '';var m=Math.floor(s/60),r=s%60;return m+':'+(r<10?'0':'')+r}
 function size(b){b=+b||0;if(b<=0)return '';if(b>=1073741824)return (b/1073741824).toFixed(1)+' GB';if(b>=1048576)return (b/1048576).toFixed(1)+' MB';return Math.round(b/1024)+' KB'}

 function build(){
  if(document.getElementById('p_conv'))return;
  var tabs=document.querySelector('.tabs'),tLib=document.getElementById('t_lib');
  if(!tabs)return;
  var tb=mk('button',null);tb.id='t_conv';tb.setAttribute('data-t','t_conv');tb.onclick=function(){tab('conv')};
  if(tLib&&tLib.nextSibling)tabs.insertBefore(tb,tLib.nextSibling);else tabs.appendChild(tb);

  var p=mk('div','pane');p.id='p_conv';
  var card=mk('div','card');
  var h=mk('h2');var hs=mk('span');hs.setAttribute('data-t','cv_h');h.appendChild(hs);
  var sub=mk('p');sub.setAttribute('data-t','cv_sub');

  var rowPick=flex(mk('div','row'));
  var bPick=mk('button','s');bPick.id='cvPick';bPick.setAttribute('data-t','cv_pick');bPick.onclick=pick;
  var bClr=mk('button','s');bClr.id='cvClear';bClr.setAttribute('data-t','cv_clear');bClr.onclick=clearDone;
  rowPick.appendChild(bPick);rowPick.appendChild(bClr);

  var list=mk('div');list.id='cvList';
  list.style.cssText='margin-top:10px;max-height:44vh;overflow:auto;display:flex;flex-direction:column;gap:6px';

  var rowF=flex(mk('div','row'));rowF.style.cssText+=';margin-top:12px;align-items:flex-end';
  var lF=mk('label');var spF=mk('span',null,t2('cv_fmt'));spF.setAttribute('data-t','cv_fmt');lF.appendChild(spF);
  var sF=mk('select');sF.id='cvFmt';FMT.forEach(function(f){var o=mk('option',null,f[1]);o.value=f[0];sF.appendChild(o)});
  sF.style.minWidth='120px';lF.appendChild(sF);
  var lQ=mk('label');var spQ=mk('span',null,t2('cv_q'));spQ.setAttribute('data-t','cv_q');lQ.appendChild(spQ);
  var sQ=mk('select');sQ.id='cvQ';QS.forEach(function(q){var o=mk('option',null,q[1]);o.value=q[0];sQ.appendChild(o)});
  sQ.value='192';sQ.style.minWidth='120px';lQ.appendChild(sQ);
  rowF.appendChild(lF);rowF.appendChild(lQ);

  var rowD=flex(mk('div','row'));rowD.style.cssText+=';margin-top:10px';
  var inD=mk('input');inD.style.flex='1 1 320px';inD.id='cvDest';inD.setAttribute('data-ph','cv_destph');inD.placeholder=t2('cv_destph');
  var bD=mk('button','s');bD.id='cvDestPick';bD.setAttribute('data-t','cv_choose');bD.onclick=pickDest;
  rowD.appendChild(inD);rowD.appendChild(bD);

  var lDel=flex(mk('label'));lDel.style.cssText+=';margin-top:10px';
  var cDel=mk('input');cDel.type='checkbox';cDel.id='cvDel';
  var sDel=mk('span');sDel.setAttribute('data-t','cv_del');
  lDel.appendChild(cDel);lDel.appendChild(sDel);

  var rowGo=flex(mk('div','row'));rowGo.style.cssText+=';margin-top:12px';
  var bGo=mk('button','big');bGo.id='cvGo';bGo.setAttribute('data-t','cv_go');bGo.onclick=start;
  var bStop=mk('button','s');bStop.id='cvStop';bStop.setAttribute('data-t','cv_stop');bStop.onclick=stop;
  bStop.classList.add('hide');
  rowGo.appendChild(bGo);rowGo.appendChild(bStop);

  var bar=mk('progress');bar.id='cvBar';bar.max=100;bar.value=0;
  bar.style.cssText='width:100%;height:10px;margin-top:12px;display:none';
  var info=mk('div');info.id='cvInfo';info.style.cssText='margin-top:8px;opacity:.85;font-size:.92em';

  card.appendChild(h);card.appendChild(sub);card.appendChild(rowPick);card.appendChild(list);
  card.appendChild(rowF);card.appendChild(rowD);card.appendChild(lDel);card.appendChild(rowGo);
  card.appendChild(bar);card.appendChild(info);
  p.appendChild(card);

  var parent=document.getElementById('p_lib')||document.getElementById('p_links');
  if(parent&&parent.parentNode)parent.parentNode.insertBefore(p,parent.nextSibling);
  else document.body.appendChild(p);

  var _tab=tab;
  tab=function(k){_tab(k);var on=(k==='conv');
   var pp=document.getElementById('p_conv');if(pp)pp.classList.toggle('on',on);
   var bb=document.getElementById('t_conv');if(bb)bb.classList.toggle('on',on);
   if(on)poll()};

  if(typeof applyLang==='function')applyLang();
  poll();
 }

 function row(it,i){
  var w=flex(mk('div','row'),10);
  w.style.cssText='padding:8px 10px;border-radius:10px;background:rgba(255,255,255,.04)';
  var box=mk('div');box.style.cssText='flex:1;min-width:0';
  var nm=mk('div',null,it.name);nm.style.cssText='font-weight:600;white-space:nowrap;overflow:hidden;text-overflow:ellipsis';
  var meta=mk('div',null,[dur(it.dur),size(it.size),it.dir].filter(Boolean).join(' · '));
  meta.style.cssText='opacity:.7;font-size:.85em;white-space:nowrap;overflow:hidden;text-overflow:ellipsis';
  box.appendChild(nm);box.appendChild(meta);
  var st=mk('div');
  var map={wait:t2('cv_wait'),run:t2('cv_run')+(it.pct?' '+it.pct+'%':''),done:t2('cv_done'),err:t2('cv_err')};
  st.textContent=map[it.status]||it.status;
  st.style.cssText='font-size:.85em;white-space:nowrap;opacity:'+(it.status==='done'?'.95':'.8')+';color:'+(it.status==='err'?'#ff8888':(it.status==='done'?'#61e08c':'inherit'));
  if(it.status==='err'&&it.msg){st.title=it.msg}
  w.appendChild(box);w.appendChild(st);
  if(it.status!=='run'){
   var x=mk('button','s',t2('cv_remove'));x.style.cssText='padding:4px 10px;font-size:.85em;flex:none';
   x.onclick=function(){api('conv/del',{i:i}).then(poll).catch(poll)};
   w.appendChild(x);
  }
  return w;
 }

 function render(d){
  last=d;
  var l=document.getElementById('cvList');if(!l)return;
  l.innerHTML='';
  var its=(d&&d.items)||[];
  if(!its.length){var e=mk('div',null,t2('cv_empty'));e.style.cssText='opacity:.75;padding:10px 2px';l.appendChild(e)}
  its.forEach(function(it,i){l.appendChild(row(it,i))});
  var bar=document.getElementById('cvBar'),info=document.getElementById('cvInfo'),go=document.getElementById('cvGo'),stopB=document.getElementById('cvStop');
  if(!bar||!info)return;
  var busy=!!(d&&d.busy);
  bar.style.display=busy?'block':'none';
  bar.value=busy?(+d.pct||0):0;
  if(go)go.disabled=busy;
  if(stopB)stopB.classList.toggle('hide',!busy);
  var nWait=its.filter(function(x){return x.status==='wait'}).length;
  var nDone=its.filter(function(x){return x.status==='done'}).length;
  var txt='';
  if(busy)txt=(d.cur?d.cur+' — ':'')+(d.pct||0)+'%';
  else if(nDone)txt=nDone+' '+t2('cv_done').toLowerCase()+(nWait?' · '+nWait+' '+t2('cv_wait'):'');
  else if(nWait)txt=nWait+' '+t2('cv_files');
  if(d&&d.err)txt=d.err;
  info.textContent=txt;
 }

 function poll(){
  if(document.body.dataset.tab!=='conv'&&!(last&&last.busy))return;
  api('conv').then(render).catch(function(){});
 }

 async function pick(){
  var b=document.getElementById('cvPick');
  if(b)b.disabled=true;
  try{
   var r=await api('conv/pick',{});
   if(r&&r.error){var i=document.getElementById('cvInfo');if(i)i.textContent=r.error}
   if(r&&r.busy){var inf=document.getElementById('cvInfo');if(inf)inf.textContent=t2('cv_pickrun');
    for(var k=0;k<900;k++){await new Promise(function(z){setTimeout(z,500)});var s=await api('conv');if(s&&!s.pick)break}
    var s2=await api('conv');render(s2);
    if(!(s2&&(s2.items||[]).length)){var i2=document.getElementById('cvInfo');if(i2)i2.textContent=t2('cv_none')}
   }
  }catch(e){}
  finally{if(b)b.disabled=false}
 }

 async function pickDest(){
  try{var r=await api('pickfolder',{});var n=0;while(r&&r.busy&&n++<600){await new Promise(function(z){setTimeout(z,1000)});r=await api('pickfolder')}
   var i=document.getElementById('cvDest');if(r&&r.path&&i)i.value=r.path}catch(e){}
 }

 async function start(){
  var f=document.getElementById('cvFmt'),q=document.getElementById('cvQ'),d=document.getElementById('cvDest'),del=document.getElementById('cvDel');
  var o={fmt:f?f.value:'mp3',q:q?q.value:'192',dest:d?d.value.trim():'',del:!!(del&&del.checked)};
  try{var r=await api('conv/start',o);
   if(r&&r.error){var i=document.getElementById('cvInfo');if(i)i.textContent=r.error}
   if(r&&r.destno){var i2=document.getElementById('cvInfo');if(i2)i2.textContent=t2('cv_destno')}
   poll()}catch(e){}
 }

 async function stop(){try{await api('conv/stop',{})}catch(e){};setTimeout(poll,300)}

 async function clearDone(){try{await api('conv/clear',{})}catch(e){};poll()}

 document.addEventListener('DOMContentLoaded',function(){
  build();
  var fmt=document.getElementById('cvFmt');
  if(fmt)fmt.addEventListener('change',function(){
   var q=document.getElementById('cvQ');
   if(q)q.disabled=(this.value==='flac'||this.value==='wav')
  });
  var lsel=document.getElementById('lang');
  if(lsel&&!lsel.__cv){lsel.__cv=1;lsel.addEventListener('change',function(){if(last)render(last)})}
  timer=setInterval(function(){
   if(document.body.dataset.tab==='conv'||(last&&last.busy))poll();
  },900);
 });
})();
