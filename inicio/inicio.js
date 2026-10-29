(function(){
  const root=document.documentElement, quieto=matchMedia('(prefers-reduced-motion: reduce)').matches;
  // Pestañas Vender / Comprar
  const tv=document.getElementById('t-v'), tc=document.getElementById('t-c'), ti=document.getElementById('titulo'), su=document.getElementById('sub'), cta=document.getElementById('cta');
  const V={v:['Lo que ya no usas,','otra persona lo quiere.','Publica tu ropa y tus cosas de casa en un minuto, gratis y sin comisión, y véndelas a gente de toda Venezuela.','Únete como vendedor fundador'],
           c:['Ropa buena,','a precio de segunda mano.','Encuentra prendas, zapatos y cosas de casa cerca de ti, con el precio en dólares y en bolívares a la tasa del BCV.','Ver prendas']};
  function sel(k){tv.setAttribute('aria-selected',k==='v');tc.setAttribute('aria-selected',k==='c');
    ti.querySelector('.a').textContent=V[k][0];ti.querySelector('.b').textContent=V[k][1];su.textContent=V[k][2];cta.textContent=V[k][3];
    ti.animate([{opacity:0,transform:'translateY(14px)'},{opacity:1,transform:'none'}],{duration:450,easing:'ease-out'})}
  tv.onclick=()=>sel('v'); tc.onclick=()=>sel('c');

  // Animaciones al bajar: solo se preparan los elementos que aún no están en pantalla (lo visible queda tal cual)
  if(!quieto && 'IntersectionObserver' in window){
    document.querySelectorAll('.pinta').forEach(h=>h.querySelectorAll('.a,.b').forEach(sp=>{
      sp.innerHTML=sp.textContent.split(' ').map((w,i)=>`<span class="w" style="transition-delay:${i*90}ms">${w}</span>`).join(' ')}));
    const io=new IntersectionObserver(es=>es.forEach(e=>{if(e.isIntersecting){e.target.classList.add('ok');io.unobserve(e.target)}}),{threshold:.18,rootMargin:'0px 0px -6% 0px'});
    root.classList.add('js');
    document.querySelectorAll('.rev,.pinta').forEach((el,i)=>{
      const r=el.getBoundingClientRect(); if(r.top<innerHeight*0.92){el.classList.add('ok')} else {el.style.transitionDelay=(i%3)*70+'ms'; io.observe(el)}
    });
  }

  // Carrusel en abanico (3D)
  const ab=document.getElementById('abanico'), it=[...ab.querySelectorAll('.ab')], abp=document.getElementById('ab-p');
  let a=0,ta=null;
  it.forEach((_,i)=>{const b=document.createElement('button');b.type='button';b.setAttribute('aria-label','Prenda '+(i+1));b.onclick=()=>irA(i);abp.appendChild(b)});
  function pintaA(){const n=it.length;it.forEach((el,i)=>{let d=i-a;if(d>n/2)d-=n;if(d<-n/2)d+=n;const k=Math.abs(d);
      el.style.transform=`translateX(${d*58}%) translateZ(${-k*140}px) rotateY(${d*-28}deg) scale(${k?0.86:1})`;
      el.style.zIndex=20-k;el.style.opacity=k>2?0:1;el.style.filter=k?`brightness(${1-k*0.18}) saturate(${1-k*0.2})`:'none';el.onclick=()=>irA(i)});
    [...abp.children].forEach((b,i)=>b.setAttribute('aria-current',i===a))}
  function irA(i){a=(i+it.length)%it.length;pintaA();if(!quieto){clearInterval(ta);ta=setInterval(()=>irA(a+1),3200)}}
  document.getElementById('ab-a').onclick=()=>irA(a-1);document.getElementById('ab-s').onclick=()=>irA(a+1);
  let x0=null;ab.addEventListener('pointerdown',e=>x0=e.clientX);ab.addEventListener('pointerup',e=>{if(x0===null)return;const dx=e.clientX-x0;x0=null;if(Math.abs(dx)>35)irA(a+(dx<0?1:-1))});
  ab.addEventListener('mouseenter',()=>clearInterval(ta));ab.addEventListener('mouseleave',()=>irA(a));
  irA(0);

  // Carrusel de pasos con puntitos
  const pa=document.getElementById('pasos'), pp=document.getElementById('pa-p'), np=pa.children.length; let p=0,tp=null;
  for(let i=0;i<np;i++){const b=document.createElement('button');b.type='button';b.setAttribute('aria-label','Paso '+(i+1));b.onclick=()=>irP(i);pp.appendChild(b)}
  function irP(i){p=(i+np)%np;pa.style.transform=`translateX(${-p*100}%)`;[...pp.children].forEach((b,k)=>b.setAttribute('aria-current',k===p));
    if(!quieto){clearInterval(tp);tp=setInterval(()=>irP(p+1),4200)}}
  let y0=null;pa.addEventListener('pointerdown',e=>y0=e.clientX);pa.addEventListener('pointerup',e=>{if(y0===null)return;const dx=e.clientX-y0;y0=null;if(Math.abs(dx)>35)irP(p+(dx<0?1:-1))});
  irP(0);
})();

// Cuenta la visita a esta página (sin nombre ni IP) para el panel de Pavito.
(function(){
  try{
    var q=new URLSearchParams(location.search),o=(q.get('utm_source')||q.get('o')||'').toLowerCase(),h='';
    try{h=document.referrer?new URL(document.referrer).hostname:''}catch(e){}
    if(!o){o=/instagram/.test(h)?'instagram':/tiktok/.test(h)?'tiktok':/whatsapp|wa\.me/.test(h)?'whatsapp':/facebook|^l\.|^lm\./.test(h)?'facebook':/google/.test(h)?'google':(h&&h!==location.hostname)?h.replace(/^www\./,''):'directo'}
    o=o.replace(/[^a-z0-9._ -]/g,'').slice(0,40)||'otro';
    var s='';for(var i=0;i<20;i++)s+='abcdefghijklmnopqrstuvwxyz0123456789'[Math.floor(Math.random()*36)];
    var k='sb_publishable_PFt4DdXlWbQEvyEgP58BZQ_CKXaoHGG';
    fetch('https://udhyuyokrxggdnnepbmr.supabase.co/rest/v1/rpc/registrar_visita',{method:'POST',keepalive:true,
      headers:{'Content-Type':'application/json',apikey:k,Authorization:'Bearer '+k},
      body:JSON.stringify({p_sesion:s,p_disp:null,p_origen:o,p_ruta:'inicio',p_plataforma:'web'})}).catch(function(){});
  }catch(e){}
})();
