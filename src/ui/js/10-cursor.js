@@INCLUDE:src/ui/data/cursors.js@@
function cssU(d){return 'url("'+d+'")'}
function curRules(M){ /* M: name -> 'url(...) hx hy' */
 var g=function(n){return M[n]||M.normal};
 return 'html,html *{cursor:'+g('normal')+',auto !important}'+
 'a,button,select,summary,label,input[type=checkbox],input[type=radio],input[type=file],.seg label,.tabs button{cursor:'+g('hover')+',pointer !important}'+
 'a[href]{cursor:'+g('link')+',pointer !important}'+
 'button:active,.seg label:active{cursor:'+g('click')+',pointer !important}'+
 'textarea,input[type=text],input[type=number],input:not([type]){cursor:'+g('text')+',text !important}'+
 'button:disabled,select:disabled,input:disabled{cursor:'+g('not_allowed')+',not-allowed !important}'+
 'progress{cursor:'+g('working')+',progress !important}'+
 '#qbtn{cursor:'+g('close')+',pointer !important}.k-open{cursor:'+g('open')+',pointer !important}.k-search{cursor:'+g('search')+',pointer !important}.k-reload{cursor:'+g('reload')+',pointer !important}#logo{cursor:'+g('home')+',pointer !important}'}
function packImgs(size,done){var names=Object.keys(CUR),left=names.length,P={};
 names.forEach(function(n){var d=CUR[n],im=new Image();im.onload=function(){var s=size/96,c=document.createElement('canvas');c.width=Math.max(1,Math.round(d[3]*s));c.height=Math.max(1,Math.round(d[4]*s));c.getContext('2d').drawImage(im,0,0,c.width,c.height);
  P[n]={u:c.toDataURL('image/png'),hx:Math.round(d[1]*s),hy:Math.round(d[2]*s),w:c.width,h:c.height};if(--left===0)done(P)};im.onerror=function(){if(--left===0)done(P)};im.src='data:image/png;base64,'+d[0]})}
function packCss(size,done){packImgs(size,function(P){var M={};for(var n in P)M[n]=cssU(P[n].u)+' '+P[n].hx+' '+P[n].hy;done(curRules(M))})}
var curSeq=0;
function fxOk(){try{return !(matchMedia('(prefers-reduced-motion: reduce)').matches||matchMedia('(pointer: coarse)').matches)}catch(e){return true}}
function applyCursor(){var st=$('cursorStyle');if(!st){st=document.createElement('style');st.id='cursorStyle';document.head.appendChild(st)}
 var v=$('curmode').value,size=parseInt($('curpx2').value,10)||32,my=++curSeq,an=$('curanim').value;
 $('curpick').classList.toggle('hide',v!=='custom');$('cursz').classList.toggle('hide',v==='default');$('curanimrow').classList.toggle('hide',v==='default');
 var useFx=v!=='default'&&an!=='off'&&fxOk();
 if(!useFx)fxStop();
 if(v==='pack'){packImgs(size,function(P){if(my!==curSeq)return;if(useFx){st.textContent='';fxStart(P,an)}else{var M={};for(var n in P)M[n]=cssU(P[n].u)+' '+P[n].hx+' '+P[n].hy;st.textContent=curRules(M)}})}
 else if(v==='custom'){var url='';try{url=localStorage.getItem('md_cursor')||''}catch(e){}
  if(!url){st.textContent='';fxStop();return}var im=new Image();im.onload=function(){if(my!==curSeq)return;var s=size/Math.max(im.width,im.height),c=document.createElement('canvas');c.width=Math.max(1,Math.round(im.width*s));c.height=Math.max(1,Math.round(im.height*s));c.getContext('2d').drawImage(im,0,0,c.width,c.height);var d=c.toDataURL('image/png');
   if(useFx){st.textContent='';fxStart({normal:{u:d,hx:1,hy:1,w:c.width,h:c.height}},an)}else{st.textContent='html,html *{cursor:'+cssU(d)+' 1 1,auto !important}'}};im.src=url}
 else{st.textContent='';fxStop()}}
var FX={};
function fxStop(){if(FX.stop)FX.stop();FX={}}
function fxStart(map,mode){fxStop();
 var el=document.createElement('div');el.id='curfx';var im=document.createElement('img');im.alt='';im.draggable=false;el.appendChild(im);document.body.appendChild(el);
 var cs=document.createElement('style');cs.id='curfxcss';cs.textContent='html.nocur,html.nocur *{cursor:none !important}';document.head.appendChild(cs);
 var S={st:null,hx:0,hy:0,x:0,y:0,px:0,rot:0,sc:1,down:false,seen:false,lsx:-99,lsy:-99,n:0,raf:0},full=(mode==='full'),root=document.documentElement;
 var SEL={dis:'button:disabled,select:disabled,input:disabled',txt:'textarea,input[type=text],input[type=number],input:not([type])',clk:'a,button,select,summary,label,input,.seg label,.tabs button'};
 function pick(t,down){if(!t||!t.closest)return 'normal';
  if(t.closest(SEL.dis))return 'not_allowed';if(t.closest(SEL.txt))return 'text';if(t.closest('a[href]'))return 'link';
  if(t.closest('#qbtn'))return down?'click':'close';if(t.closest('.k-open'))return down?'click':'open';if(t.closest('.k-search'))return down?'click':'search';if(t.closest('.k-reload'))return down?'click':'reload';if(t.closest('#logo'))return 'home';
  if(t.closest(SEL.clk))return down?'click':'hover';if(t.closest('progress'))return 'working';return 'normal'}
 function setSt(s){if(s===S.st)return;S.st=s;var m=map[s]||map.normal;if(!m)return;im.src=m.u;im.style.width=m.w+'px';im.style.height=m.h+'px';S.hx=m.hx;S.hy=m.hy;im.style.transformOrigin=m.hx+'px '+m.hy+'px'}
 function place(){el.style.transform='translate('+(S.x-S.hx)+'px,'+(S.y-S.hy)+'px)'}
 function spark(){var n=document.querySelectorAll('.fxs').length;if(n>36)return;var s=document.createElement('span');s.className='fxs';s.textContent='\u2726';s.style.left=(S.x+(Math.random()*16-8))+'px';s.style.top=(S.y+(Math.random()*16-4))+'px';s.style.color=['#22d3ee','#a78bfa','#f472b6'][S.n++%3];s.style.fontSize=(8+Math.random()*8)+'px';s.addEventListener('animationend',function(){s.remove()});document.body.appendChild(s)}
 function mm(e){S.x=e.clientX;S.y=e.clientY;S.seen=true;setSt(pick(e.target,S.down));el.style.display='block';root.classList.add('nocur');place();
  if(full){var dx=S.x-S.lsx,dy=S.y-S.lsy;if(dx*dx+dy*dy>180){S.lsx=S.x;S.lsy=S.y;spark()}}}
 function md(e){S.down=true;setSt(pick(e.target,true))}
 function mu(e){S.down=false;setSt(pick(e.target,false))}
 function ml(){el.style.display='none'}
 function loop(){var vx=S.x-S.px;S.px=S.x;var tr=Math.max(-16,Math.min(16,vx*0.7));S.rot+=(tr-S.rot)*0.22;S.sc+=((S.down?0.8:1)-S.sc)*0.3;
  if(S.seen)im.style.transform='rotate('+S.rot.toFixed(2)+'deg) scale('+S.sc.toFixed(3)+')';S.raf=requestAnimationFrame(loop)}
 document.addEventListener('mousemove',mm,true);document.addEventListener('mousedown',md,true);document.addEventListener('mouseup',mu,true);document.documentElement.addEventListener('mouseleave',ml);
 setSt('normal');S.raf=requestAnimationFrame(loop);
 FX.stop=function(){cancelAnimationFrame(S.raf);document.removeEventListener('mousemove',mm,true);document.removeEventListener('mousedown',md,true);document.removeEventListener('mouseup',mu,true);document.documentElement.removeEventListener('mouseleave',ml);root.classList.remove('nocur');el.remove();cs.remove();var a=document.querySelectorAll('.fxs');for(var i=0;i<a.length;i++)a[i].remove()}}
$('curfile').addEventListener('change',function(){var f=this.files[0];if(!f)return;var r=new FileReader();r.onload=function(){var im=new Image();im.onload=function(){var s=96/Math.max(im.width,im.height),c=document.createElement('canvas');c.width=Math.max(1,Math.round(im.width*s));c.height=Math.max(1,Math.round(im.height*s));c.getContext('2d').drawImage(im,0,0,c.width,c.height);try{localStorage.setItem('md_cursor',c.toDataURL('image/png'))}catch(e){}applyCursor()};im.src=r.result};r.readAsDataURL(f)});
applyCursor();
