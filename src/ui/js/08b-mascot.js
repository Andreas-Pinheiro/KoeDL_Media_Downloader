/* Mascote KoeDL: 5 poses (idle, start, down, ok, err), todas no mesmo tamanho/ponto, dentro de uma moldura */
const MASC={idle:'data:image/webp;base64,@@B64:assets/mascote/idle.webp@@',start:'data:image/webp;base64,@@B64:assets/mascote/start.webp@@',down:'data:image/webp;base64,@@B64:assets/mascote/down.webp@@',ok:'data:image/webp;base64,@@B64:assets/mascote/ok.webp@@',err:'data:image/webp;base64,@@B64:assets/mascote/err.webp@@'};
function mkMascot(host,state,caption){var w=document.createElement('div');w.className='mascot';w.innerHTML='<div class="mf"></div><img class="mi" alt=""><div class="mo"></div>';host.appendChild(w);
 var im=w.querySelector('.mi'),cap=null;if(caption){cap=document.createElement('div');cap.className='mcap';host.appendChild(cap)}
 w.set=function(s){if(w.dataset.s===s)return;w.dataset.s=s;im.style.animation='none';void im.offsetWidth;im.style.animation='';im.src=MASC[s];if(cap){cap.dataset.t='m_'+s;cap.textContent=t('m_'+s)}};
 w.set(state||'idle');return w}
(function(){
 var MS={fin:null,ft:0},D=null,Q=null;
  var mq=document.createElement('div');mq.id='mq';var qc=$('qcol');if(qc&&qc.parentNode){qc.parentNode.appendChild(mq);Q=mkMascot(mq,'idle',true)}
 function now(){var s=lastStatus||{};
  if(running)return (s.pct>1)?'down':'start';
  if(MS.fin)return MS.fin;
  if(P&&P.err&&!(P.items&&P.items.length))return 'err';
  return 'idle'}
 function upd(){var st=now();if(Q)Q.set(st);}
 /* quando um download termina, mostra "ok" ou "erro" ate o proximo link/download */
 var was=false;
 var _ss=showStatus;showStatus=function(s){_ss.apply(this,arguments);
  if(s.running){was=true;MS.fin=null}
  else if(was){was=false;var txt=String(s.status||'');MS.fin=/erro|error|falh|fail/i.test(txt)||(s.fails&&s.fails.length)?'err':(/parad|stopp/i.test(txt)?null:'ok');clearTimeout(MS.ft);MS.ft=setTimeout(function(){MS.fin=null;upd()},45000)}
  upd()};
 var _r=render;render=function(){_r.apply(this,arguments);upd()};
 var u=$('urls');if(u)u.addEventListener('input',function(){MS.fin=null;upd()});
 setInterval(upd,1500);upd();
 window.mkMascotIn=mkMascot;
})();
