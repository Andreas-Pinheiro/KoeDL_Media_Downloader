var lastClip='';async function clipPaste(){try{if(!$('autoclip').checked||$('urls').value.trim()||cur!=='links')return;var r=await api('clip',{});var x=((r&&r.text)||'').trim();
 if(!x||x===lastClip||!/^https?:\/\/\S+$/.test(x))return;lastClip=x;$('urls').value=x}catch(e){}}
addEventListener('focus',clipPaste);setTimeout(clipPaste,1500);
/* atalhos do teclado */
addEventListener('keydown',function(e){if(!(e.ctrlKey||e.metaKey))return;var k=e.key;
 if(k==='Enter'){e.preventDefault();go(cur==='links'&&P.items.length&&document.activeElement&&document.activeElement.closest&&document.activeElement.closest('#colR')?'pick':undefined)}
 else if(k==='l'||k==='L'){e.preventDefault();tab('links');$('urls').focus()}
 else if(k>='1'&&k<='5'){e.preventDefault();tab(['links','q','lib','cfg','sup'][+k-1])}});
var _al=applyLang;applyLang=function(){_al.apply(this,arguments);renderQ();renderH()};
loadHist();renderQ();setTimeout(qLoad,800);
async function chk(){const u=opts().urls[0];if(!u)return;$('ck').textContent=t('ck_ing');await api('info',{url:u});
for(let i=0;i<90;i++){await new Promise(r=>setTimeout(r,700));const r=await api('infostate');if(!r.busy){$('ck').textContent=r.error?(t('ck_err')+r.error):(r.title+' · '+r.count+t('ck_cnt')+(r.ex?' · '+r.ex:''));return}}$('ck').textContent=t('ck_slow')}
var UPDX={},UPDGO=false;
$('updlater').onclick=function(){UPDX[$('updt').textContent.match(/[0-9]+(\.[0-9]+)+/)[0]]=1;$('updb').classList.add('hide')};
$('updgo').onclick=async function(){var r=await api('applyupd',{});if(r&&r.error){alert(r.error);return}UPDGO=true;$('updt').textContent=t('upd_restart');$('updgo').classList.add('hide');$('updlater').classList.add('hide')};
var CHKW=false;async function chkUpd(){UPDX={};UPDGO=false;CHKW=true;$('chkbtn').disabled=true;$('chkmsg').textContent=t('chk_run');await api('chkupd',{})}
function chkDone(s){if(!CHKW||!s.chk||s.chk==='run')return;CHKW=false;$('chkbtn').disabled=false;$('chkmsg').textContent=s.chk==='same'?t('chk_same').replace('{c}',s.appver||''):s.chk==='new'?t('chk_new').replace('{v}',s.updavail||''):t('chk_err')}
async function upd(){const r=await api('update',{});if(r.error)alert(r.error)}
async function shortcuts(){const r=await api('shortcut',{});alert(r.msg||r.error||'ok')}
/* ---- links: um lugar so, avulso e playlist juntos ---- */
/* Cada link colado na caixa vira linhas na lista de selecao: video/musica avulso = 1 linha,
   playlist = todas as faixas. Tirar o link da caixa tira as linhas dele. */
function isUrl(u){return /^https?:\/\/\S+$/i.test(String(u||''))}
function isPl(u){return /(\/playlist\?|list=|music\.youtube\.com\/playlist)/i.test(String(u||''))}
function plUrls(){return (opts().urls||[]).filter(isUrl)}
var PLS={},PLBusy=false,PLTok=0;
async function plSync(){if(PLBusy)return;var tok=++PLTok,links=plUrls(),keep={};links.forEach(function(u){keep[u]=1});
 P.items=P.items.filter(function(x){return keep[x.src]});render();if(tok!==PLTok)return;
 var pend=links.filter(function(u){return !PLS[u]});if(!pend.length)return;
 PLBusy=true;P.busy=true;
 try{for(var i=0;i<pend.length;i++){var u=pend[i];if(tok!==PLTok)return;
  if(isPl(u)&&$('noPl')&&$('noPl').checked){PLS[u]=1;continue}
  $('plinfo').textContent=(pend.length>1?'('+(i+1)+'/'+pend.length+') ':'')+t('pl_load');P.url=u;
  await api('pl/load',{url:u,browsers:common().browsers,nock:$('nock').checked});
  var r=null;for(var k=0;k<300;k++){await new Promise(function(res){setTimeout(res,400)});if(tok!==PLTok)return;r=await api('pl?from=0');if(r&&!r.busy)break}
  var its=(r&&r.items)||[],base=P.items.length;
  if(r&&r.title&&!P.title)P.title=r.title;
  its.forEach(function(it,j){if(P.items.some(function(x){return x.url===it.url}))return;
   it.idx=base+j+1;it.src=u;it.checked=!it.unavail;it.type=(radio('pm')==='v'?'v':'a');P.items.push(it)});
  PLS[u]=1;
  if(!its.length&&r&&r.err)$('plinfo').textContent=t('pl_fail')+r.err;
  render()}
 }catch(e){}finally{PLBusy=false;P.busy=false;render()}
 if(P.items.length&&innerWidth<900){try{$('colR').scrollIntoView({block:'start'})}catch(e){}}}
/* compatibilidade: o botao antigo da playlist agora so aponta para a caixa de links */
async function plLoad(u){if(typeof u==='string'&&u.trim()){$('urls').value=u.trim();plUrls().forEach(function(x){delete PLS[x]});PLTok++}plSync()}
var plAutoT=null;
function plAuto(){clearTimeout(plAutoT);plAutoT=setTimeout(plSync,700)}
addEventListener('DOMContentLoaded',function(){var ta=$('urls');
 if(ta){ta.addEventListener('input',plAuto);ta.addEventListener('paste',function(){setTimeout(plSync,300)})}
 var e=$('plurl');if(e){var row=e.closest('.row')||e.parentElement;if(row)row.style.display='none'}else{var b0=$('plbtn');if(b0)b0.style.display='none'}
 var b=$('plbtn');if(b)b.style.display='none'})
