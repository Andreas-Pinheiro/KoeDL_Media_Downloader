/* Avisos e confirmações do próprio programa.
   Antes usávamos alert()/confirm() do navegador, que apareciam como uma janelinha do sistema
   com o endereço "127.0.0.1:8765 diz" em cima — parecia erro de outra coisa e cortava o visual.
   Aqui a caixa é montada na página, segue o tema e devolve Promise:
     KAlert("texto")            -> Promise<true>            (só o botão OK)
     KConfirm("texto")          -> Promise<true|false>      (OK / Cancelar)
   Enter = OK, Esc = Cancelar, clique fora = fechar. */
(function(){
 var wrap=null,cardEl=null,resolver=null,mode='alert';

 function txt(k,fb){ try{ var v=(typeof t==='function')?t(k):k; return (v&&v!==k)?v:fb }catch(e){ return fb } }

 function finish(val){
  if(!resolver) return;
  var r=resolver; resolver=null;
  if(wrap){ wrap.style.display='none' }
  try{ r(!!val) }catch(e){}
 }

 function onKey(e){
  if(!resolver) return;
  if(e.key==='Escape'){ e.preventDefault(); finish(mode!=='alert') }
  else if(e.key==='Enter'){ e.preventDefault(); finish(true) }
 }

 function ensure(){
  if(wrap) return wrap;
  wrap=document.createElement('div');
  wrap.id='kDlgWrap';
  wrap.style.cssText='position:fixed;inset:0;z-index:9999;display:none;place-items:center;'+
   'background:rgba(5,7,18,.68)';
  wrap.addEventListener('mousedown',function(e){ if(e.target===wrap) finish(mode!=='alert') });

  cardEl=document.createElement('div');
  cardEl.setAttribute('role','dialog');
  cardEl.setAttribute('aria-modal','true');
  cardEl.style.cssText='max-width:430px;width:calc(100% - 32px);box-sizing:border-box;'+
   'background:var(--card2,#171a2c);color:var(--fg,#e9e7ff);border:1px solid var(--line,#2a2f47);'+
   'border-radius:16px;padding:20px 20px 16px;box-shadow:0 24px 60px rgba(0,0,0,.55);'+
   'font:inherit;line-height:1.5';

  var msg=document.createElement('div');
  msg.id='kDlgMsg';
  msg.style.cssText='font-size:15px;white-space:pre-wrap;word-break:break-word';

  var row=document.createElement('div');
  row.style.cssText='display:flex;justify-content:flex-end;gap:8px;margin-top:18px;flex-wrap:wrap';

  var bNo=document.createElement('button');
  bNo.id='kDlgNo';bNo.className='s';bNo.type='button';
  bNo.style.cssText='min-width:96px';
  bNo.onclick=function(){finish(false)};

  var bOk=document.createElement('button');
  bOk.id='kDlgOk';bOk.type='button';
  bOk.style.cssText='min-width:96px;font-weight:600';
  bOk.onclick=function(){finish(true)};

  row.appendChild(bNo);row.appendChild(bOk);
  cardEl.appendChild(msg);cardEl.appendChild(row);
  wrap.appendChild(cardEl);
  (document.body||document.documentElement).appendChild(wrap);
  document.addEventListener('keydown',onKey,true);
  return wrap;
 }

 function open(m,message,okLabel,noLabel){
  var w=ensure();
  if(resolver) finish(false);          // duas caixas ao mesmo tempo: fecha a anterior
  mode=(m==='confirm')?'confirm':'alert';
  document.getElementById('kDlgMsg').textContent=String(message==null?'':message);
  var bOk=document.getElementById('kDlgOk'),bNo=document.getElementById('kDlgNo');
  bOk.textContent=okLabel||txt('dlg_ok','OK');
  bNo.textContent=noLabel||txt('dlg_cancel',mode==='confirm'?'Cancel':'Cancelar');
  bNo.style.display=(mode==='confirm')?'':'none';
  w.style.display='grid';
  try{ bOk.focus() }catch(e){}
  return new Promise(function(res){ resolver=res });
 }

 window.KAlert=function(message,okLabel){ return open('alert',message,okLabel) };
 window.KConfirm=function(message,okLabel,noLabel){ return open('confirm',message,okLabel,noLabel) };
})();
