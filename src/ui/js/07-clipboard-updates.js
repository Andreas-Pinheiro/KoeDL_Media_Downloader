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
/* ---- playlist tab ---- */
/* um lugar so para colar links: usa o campo da playlist se ele existir, senao o primeiro link colado */
function plUrl(){var e=$('plurl');return((e&&e.value.trim())||'')||((opts().urls||[])[0]||'')}
function isPl(u){return /(\/playlist\?|list=|music\.youtube\.com\/playlist)/i.test(String(u||''))}
async function plLoad(u){u=(typeof u==='string'?u.trim():'')||plUrl();if(!u)return alert(t('pl_need'));P={items:[],from:0,busy:true,title:'',url:u};plSeen=false;render();$('plinfo').textContent=t('pl_load');await api('pl/load',{url:u,browsers:common().browsers,nock:$('nock').checked});plPoll()}
/* link de playlist colado na area principal carrega a lista de faixas sozinho */
var plAutoT=null;
function plAuto(){clearTimeout(plAutoT);plAutoT=setTimeout(function(){try{var a=opts().urls;if(a.length!==1)return;var u=a[0];if(!isPl(u)||P.busy||P.url===u)return;if($('noPl')&&$('noPl').checked)return;plLoad(u)}catch(e){}},800)}
addEventListener('DOMContentLoaded',function(){var ta=$('urls');if(ta){ta.addEventListener('input',plAuto);ta.addEventListener('paste',function(){setTimeout(plAuto,250)})}
 var e=$('plurl'),b=$('plbtn');if(e)e.style.display='none';if(b)b.style.display='none'})
var plSeen=false;
async function plPoll(){try{const r=await api('pl?from='+P.from);const pm=radio('pm');
for(const it of r.items){it.checked=!it.unavail;it.type=pm==='v'?'v':'a';P.items.push(it)}P.from=r.total;P.title=r.title||P.title;P.busy=r.busy;P.err=r.err;render()
if(P.items.length&&!plSeen){plSeen=true;if(innerWidth<900){try{$('colR').scrollIntoView({block:'start'})}catch(e){}}}
if(r.busy)setTimeout(plPoll,700);else if(!P.items.length&&r.err)$('plinfo').textContent=t('pl_fail')+r.err}catch(e){}}
