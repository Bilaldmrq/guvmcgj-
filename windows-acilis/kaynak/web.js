import * as THREE from 'three';
import {EffectComposer} from 'three/examples/jsm/postprocessing/EffectComposer.js';
import {RenderPass} from 'three/examples/jsm/postprocessing/RenderPass.js';
import {UnrealBloomPass} from 'three/examples/jsm/postprocessing/UnrealBloomPass.js';
import {OutputPass} from 'three/examples/jsm/postprocessing/OutputPass.js';
import {RoomEnvironment} from 'three/examples/jsm/environments/RoomEnvironment.js';

// ===== AÇILIŞ: Three.js ile gerçek zamanlı 3D ark reaktörü =====
const intro=document.getElementById('intro'),$=id=>document.getElementById(id);

// --- Sahne ---
const cv=$('ir3d');let renderer;
try{renderer=new THREE.WebGLRenderer({canvas:cv,antialias:true,powerPreference:'high-performance'});}catch(e){window.__introKill();throw e;}
renderer.setPixelRatio(Math.min(devicePixelRatio,2));
renderer.toneMapping=THREE.ACESFilmicToneMapping;renderer.toneMappingExposure=1.05;
const scene=new THREE.Scene();scene.background=new THREE.Color(0x020407);
const pmrem=new THREE.PMREMGenerator(renderer);
scene.environment=pmrem.fromScene(new RoomEnvironment(renderer),.04).texture;
const camera=new THREE.PerspectiveCamera(35,1,.05,200);

const steel=new THREE.MeshStandardMaterial({color:0xaab3bd,metalness:1,roughness:.26,envMapIntensity:.32});
const gunmetal=new THREE.MeshStandardMaterial({color:0x2b3138,metalness:1,roughness:.42,envMapIntensity:.22});
const copper=new THREE.MeshStandardMaterial({color:0xd27a3e,metalness:1,roughness:.3,envMapIntensity:.3});
const glow=new THREE.MeshStandardMaterial({color:0x000000,emissive:0x45e8ff,emissiveIntensity:0,toneMapped:false});
const coreM=new THREE.MeshStandardMaterial({color:0x000000,emissive:0xd8fdff,emissiveIntensity:0,toneMapped:false});

const R=new THREE.Group();scene.add(R);
const add=(geo,mat,f)=>{const m=new THREE.Mesh(geo,mat);f&&f(m);R.add(m);return m;};
const ring=(r,t,mat,z=0,seg=160)=>add(new THREE.TorusGeometry(r,t,24,seg),mat,m=>m.position.z=z);
// gövde
add(new THREE.CylinderGeometry(3.45,3.45,.5,128),gunmetal,m=>{m.rotation.x=Math.PI/2;m.position.z=-.45;});
ring(3.32,.17,steel,0);ring(3.02,.06,steel,.12);ring(2.98,.05,gunmetal,-.05);
for(let i=0;i<16;i++){const a=i/16*Math.PI*2;add(new THREE.CylinderGeometry(.07,.07,.12,16),steel,m=>{m.rotation.x=Math.PI/2;m.position.set(Math.cos(a)*3.17,Math.sin(a)*3.17,.16);});}
// bobin halkasının altındaki ışık (sadece aralardan sızar)
add(new THREE.RingGeometry(1.75,2.75,128),glow,m=>m.position.z=-.19);
// 10 bakır bobin
for(let i=0;i<10;i++){const g=new THREE.Group();g.rotation.z=i/10*Math.PI*2;R.add(g);
  const core=new THREE.Mesh(new THREE.BoxGeometry(.42,.95,.36),gunmetal);core.position.y=2.25;g.add(core);
  for(let k=0;k<9;k++){const w=new THREE.Mesh(new THREE.TorusGeometry(.29,.042,10,28),copper);w.rotation.x=Math.PI/2;w.scale.set(1,1,.78);w.position.y=1.86+k*.098;g.add(w);}
  const cap=new THREE.Mesh(new THREE.BoxGeometry(.66,.07,.46),steel);cap.position.y=2.78;g.add(cap);
  const cap2=cap.clone();cap2.position.y=1.72;g.add(cap2);}
// iç halka + ışık halkası
ring(1.56,.12,steel,.05);ring(1.36,.035,glow,.08);ring(1.22,.07,gunmetal,0);
for(let i=0;i<3;i++){const a=i/3*Math.PI*2+Math.PI/2;add(new THREE.BoxGeometry(.12,.5,.12),steel,m=>{m.rotation.z=a-Math.PI/2;m.position.set(Math.cos(a)*1.38,Math.sin(a)*1.38,.02);});}
// üçgen (Mark VI)
add(new THREE.TorusGeometry(1.08,.085,12,3),steel,m=>{m.rotation.z=-Math.PI/2;m.position.z=.12;});
const tri=add(new THREE.TorusGeometry(.92,.06,12,3),glow,m=>{m.rotation.z=-Math.PI/2;m.position.z=.18;});
// çekirdek
const core=add(new THREE.SphereGeometry(.5,48,24),coreM,m=>{m.scale.z=.35;m.position.z=.1;});
const light=new THREE.PointLight(0x7ff6ff,0,0,2);light.position.z=.9;R.add(light);
const rim=new THREE.DirectionalLight(0x9fc4ff,.5);rim.position.set(-6,7,6);scene.add(rim);

// kıvılcımlar
const N=700,pPos=new Float32Array(N*3),pVel=new Float32Array(N*3);let pLife=0;
const pGeo=new THREE.BufferGeometry();pGeo.setAttribute('position',new THREE.BufferAttribute(pPos,3));
const pMat=new THREE.PointsMaterial({color:0x9ff7ff,size:.05,transparent:true,opacity:0,blending:THREE.AdditiveBlending,depthWrite:false,toneMapped:false});
R.add(new THREE.Points(pGeo,pMat));
function sparks(){for(let i=0;i<N;i++){pPos[i*3]=pPos[i*3+1]=0;pPos[i*3+2]=.3;const a=Math.random()*Math.PI*2,z=Math.random()*2-1,s=.06+Math.random()*.22,r=Math.sqrt(1-z*z);
  pVel[i*3]=Math.cos(a)*r*s;pVel[i*3+1]=Math.sin(a)*r*s;pVel[i*3+2]=Math.abs(z)*s*.6;}pLife=1;}

const composer=new EffectComposer(renderer);composer.addPass(new RenderPass(scene,camera));
const bloom=new UnrealBloomPass(new THREE.Vector2(1,1),.3,.4,.9);composer.addPass(bloom);composer.addPass(new OutputPass());
function resize(){const w=innerWidth,h=innerHeight;renderer.setSize(w,h,false);composer.setSize(w,h);bloom.resolution.set(w/2,h/2);camera.aspect=w/h;camera.updateProjectionMatrix();}
resize();addEventListener('resize',resize);

// --- Durum ve tween ---
const S={power:0,camT:0,dolly:0,logo:0,mode:'boot'};
const tweens=[],eio=e=>e<.5?4*e*e*e:1-Math.pow(-2*e+2,3)/2,ein=e=>e*e*e;
const tween=(k,to,dur,ease=eio)=>new Promise(res=>tweens.push({k,from:S[k],to,dur,t0:performance.now(),ease,res}));
const lerp=(a,b,t)=>a+(b-a)*t,A=new THREE.Vector3(8.2,3.8,10.5),F=new THREE.Vector3(0,0,15),tmp=new THREE.Vector3();
let flick=1,running=true,triA=0,lastT=0;
const clk=new THREE.Clock();
function frame(){if(!running)return;requestAnimationFrame(frame);const t=clk.getElapsedTime(),now=performance.now();
  for(let i=tweens.length-1;i>=0;i--){const w=tweens[i],p=Math.min((now-w.t0)/w.dur,1);S[w.k]=lerp(w.from,w.to,w.ease(p));if(p>=1){tweens.splice(i,1);w.res();}}
  const P=S.power*flick*(1+Math.sin(t*31)*.015);
  glow.emissiveIntensity=P*1.05;coreM.emissiveIntensity=.15+P*3.4;light.intensity=P*9;bloom.strength=.15+Math.min(P,2.4)*.3;
  const dt=t-lastT;lastT=t;if(S.mode==='logo'){const k=Math.PI*2/3,tg=Math.round(triA/k)*k;triA=Math.abs(tg-triA)<.002?tg:triA+(tg-triA)*Math.min(1,dt*5);}else if(S.power>1.05)triA+=dt*(S.power-1)*7;
  tri.rotation.z=-Math.PI/2+triA;
  if(S.mode==='logo'){
    const w=innerWidth,h=innerHeight,D=Math.min(h*.26,w*.46),d=7.3*h/(.6306*D),vis=.6306*d;
    R.position.y=vis*.16;camera.fov=35;camera.position.set(Math.sin(t*.35)*.6,Math.cos(t*.3)*.3,d*(1-S.logo*.06));camera.lookAt(0,0,0);
    R.rotation.y=Math.sin(t*.4)*.12;R.rotation.x=Math.cos(t*.33)*.06;
  }else{
    tmp.lerpVectors(A,F,S.camT);const o=(1-S.camT)*.5;tmp.x+=Math.sin(t*.25)*o;tmp.y+=Math.cos(t*.2)*o;
    tmp.z=lerp(tmp.z,.75,S.dolly);tmp.x*=1-S.dolly;tmp.y*=1-S.dolly;
    camera.position.copy(tmp);camera.fov=lerp(35,78,S.dolly*S.dolly);camera.lookAt(0,0,0);
    if(S.dolly>0)camera.rotation.z=S.dolly*S.dolly*.6;
  }
  camera.updateProjectionMatrix();
  if(pLife>0){pLife-=.006;for(let i=0;i<N*3;i++){pPos[i]+=pVel[i];pVel[i]*=.985;}pGeo.attributes.position.needsUpdate=true;pMat.opacity=Math.max(pLife,0);}
  composer.render();}
frame();window.__introReady=true;

// --- Ses (Web Audio sentezi) ---
let AC,master;
function initAudio(){try{AC=new(window.AudioContext||window.webkitAudioContext)();master=AC.createGain();master.gain.value=.85;master.connect(AC.destination);}catch(e){}}
function tone(f,d,v,type='sine',f2){if(!AC)return;const t=AC.currentTime,o=AC.createOscillator(),a=AC.createGain();o.type=type;o.frequency.setValueAtTime(f,t);if(f2)o.frequency.exponentialRampToValueAtTime(f2,t+d);
  a.gain.setValueAtTime(v,t);a.gain.exponentialRampToValueAtTime(.0001,t+d);o.connect(a).connect(master);o.start(t);o.stop(t+d+.05);}
function noise(d,v,f0,f1,type='lowpass'){if(!AC)return;const t=AC.currentTime,len=AC.sampleRate*d|0,b=AC.createBuffer(1,len,AC.sampleRate),ch=b.getChannelData(0);for(let i=0;i<len;i++)ch[i]=Math.random()*2-1;
  const s=AC.createBufferSource(),fl=AC.createBiquadFilter(),a=AC.createGain();s.buffer=b;fl.type=type;fl.frequency.setValueAtTime(f0,t);fl.frequency.exponentialRampToValueAtTime(f1,t+d);
  a.gain.setValueAtTime(v,t);a.gain.exponentialRampToValueAtTime(.0001,t+d);s.connect(fl).connect(a).connect(master);s.start(t);}
const zap=()=>{noise(.08,.35,6000,1500,'bandpass');tone(60,.09,.18,'sawtooth');};
function hum(d){if(!AC)return()=>{};const t=AC.currentTime,a=AC.createGain(),fl=AC.createBiquadFilter(),o1=AC.createOscillator(),o2=AC.createOscillator();
  o1.type='sawtooth';o2.type='sine';o1.frequency.setValueAtTime(40,t);o1.frequency.exponentialRampToValueAtTime(110,t+d);o2.frequency.setValueAtTime(80,t);o2.frequency.exponentialRampToValueAtTime(660,t+d);
  fl.type='lowpass';fl.Q.value=5;fl.frequency.setValueAtTime(160,t);fl.frequency.exponentialRampToValueAtTime(1800,t+d);
  a.gain.setValueAtTime(.0001,t);a.gain.exponentialRampToValueAtTime(.1,t+1.4);
  o1.connect(fl);o2.connect(fl);fl.connect(a).connect(master);o1.start(t);o2.start(t);
  let s=false;return()=>{if(s)return;s=true;const n=AC.currentTime;a.gain.cancelScheduledValues(n);a.gain.setValueAtTime(Math.max(a.gain.value,.0002),n);a.gain.exponentialRampToValueAtTime(.0001,n+.4);o1.stop(n+.45);o2.stop(n+.45);};}
const buzz=p=>{try{navigator.vibrate&&navigator.vibrate(p)}catch(e){}};

// --- HUD metni ---
const pad=n=>String(n).padStart(2,'0');
const clock=setInterval(()=>{const d=new Date();$('iClock').textContent=pad(d.getHours())+':'+pad(d.getMinutes())+':'+pad(d.getSeconds());},250);
let msgTok=0;async function msg(txt){const my=++msgTok,el=$('iMsg');for(let i=1;i<=txt.length;i++){if(my!==msgTok)return;el.textContent=txt.slice(0,i);await sleep(22);}}
const pctTick=setInterval(()=>{$('iPct').textContent=String(Math.round(Math.min(S.power,1)*100)).padStart(3,'0');},50);

// --- Sekans ---
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
let started=false,done=false,run=0,stopHum=()=>{};
let step;
async function boot(){
  if(started)return;started=true;if(!AC)initAudio();
  const my=++run;step=async ms=>{await sleep(ms);if(done||my!==run)throw 0;};
  intro.classList.add('live');noise(.3,.45,2500,150);tone(150,.2,.22,'square',55);buzz(30);
  try{
    msg('ARK REAKTÖRÜ // ATEŞLEME');await step(650);
    for(const[p,ms]of[[.55,55],[0,130],[.9,45],[0,280],[.3,70],[0,110],[1,40],[.15,90]]){S.power=p;if(p>0){zap();buzz(15);}await step(ms);}
    stopHum=hum(4.4);tween('power',1,3600);tween('camT',1,4400);
    await step(300);msg('J.A.R.V.I.S. ÇEVRİMİÇİ');
    await step(1300);msg('REPULSÖRLER KALİBRE EDİLDİ');
    await step(1300);msg('ZIRH BÜTÜNLÜĞÜ %100');
    await step(1500);msg('ÇIKIŞ 3 GW // AŞIRI YÜK');
    stopHum();tone(140,1.5,.12,'sawtooth',2400);tone(280,1.5,.06,'sine',4800);buzz(1400);
    tween('power',2.4,1500,ein);await tween('dolly',1,1550,ein);if(done||my!==run)return;
    // beyaz patlama
    noise(2.2,.6,3000,40);tone(65,1.6,.9,'sine',26);buzz([90,40,140]);
    const fl=$('iFlash').animate([{opacity:1},{opacity:1,offset:.2},{opacity:0}],{duration:1900,easing:'ease-out',fill:'forwards'});
    S.mode='logo';S.dolly=0;S.power=1.15;camera.rotation.z=0;sparks();tween('logo',1,6000,t=>t);
    intro.classList.add('logo');msg('HOŞ GELDİNİZ, EFENDİM.');
    await step(2600);home(false);
  }catch(e){}
}
function home(skipped){
  if(intro.classList.contains('home'))return;done=true;stopHum();tweens.length=0;
  if(skipped){$('iFlash').animate([{opacity:.85},{opacity:0}],{duration:900,easing:'ease-out'});S.dolly=0;S.camT=1;camera.rotation.z=0;S.logo=0;tween('logo',1,6000,t=>t);}
  S.mode='logo';S.power=1.15;
  intro.classList.add('live','logo','home');intro.removeAttribute('role');window.__greet();
  msgTok++;msg('TÜM SİSTEMLER NOMİNAL');
}
function replay(){
  run++;done=false;started=false;msgTok++;tweens.length=0;triA=0;
  Object.assign(S,{power:0,camT:0,dolly:0,logo:0,mode:'boot'});camera.rotation.z=0;R.position.set(0,0,0);R.rotation.set(0,0,0);
  intro.className='live';$('iMsg').innerHTML='&nbsp;';
  boot();
}
intro.addEventListener('click',()=>{if(!intro.classList.contains('home'))boot();});
intro.addEventListener('keydown',e=>{if(!started&&(e.key==='Enter'||e.key===' ')){e.preventDefault();boot();}});
$('iSkip').addEventListener('click',e=>{e.stopPropagation();home(true);});
$('iReplay').addEventListener('click',e=>{e.stopPropagation();replay();});
